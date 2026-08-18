/**
 * Firestore security-rules test suite for the multi-tenant Shoe Store.
 *
 * These tests are the proof that the isolation actually holds — they exercise
 * the rules against the real Firestore emulator, including the cases that are
 * easy to get wrong (an employee touching a colleague's tenant, a user
 * promoting themselves to admin, a tenant hop via `ownerId`).
 *
 * Run:
 *   cd test/firestore_rules
 *   npm install
 *   npm test          # starts the emulator and runs mocha
 */

const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs,
        query, where, orderBy, setLogLevel } = require('firebase/firestore');

// UIDs
const OWNER_A = 'ownerA';
const EMP_A = 'employeeA';
const OWNER_B = 'ownerB';

let testEnv;

const userDoc = (uid, ownerId, role, isActive = true) => ({
  ownerId,
  name: `user-${uid}`,
  email: `${uid}@example.com`,
  role,
  isActive,
  storeName: null,
  createdAt: new Date(),
});

const saleDoc = (createdById, overrides = {}) => ({
  customerId: 'cust1',
  customerName: 'عميل',
  items: [{ inventoryId: 'inv1', brand: 'Nike', productName: 'Air', size: '42',
            quantity: 1, priceAtSale: 100 }],
  totalAmount: 100,
  status: 'paid',
  saleType: 'normal',
  notes: null,
  createdById,
  createdByName: 'user',
  saleDate: new Date(),
  createdAt: new Date(),
  ...overrides,
});

before(async function () {
  this.timeout(30000);
  setLogLevel('error');

  testEnv = await initializeTestEnvironment({
    projectId: 'shoe-store-rules-test',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  // Seed two independent tenants, bypassing the rules.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', OWNER_A), userDoc(OWNER_A, OWNER_A, 'admin'));
    await setDoc(doc(db, 'users', EMP_A), userDoc(EMP_A, OWNER_A, 'employee'));
    await setDoc(doc(db, 'users', OWNER_B), userDoc(OWNER_B, OWNER_B, 'admin'));

    await setDoc(doc(db, 'users', OWNER_A, 'inventory', 'inv1'), {
      brand: 'Nike', productName: 'Air', size: '42',
      openingBalance: 10, soldQuantity: 0, currentPrice: 100,
      createdAt: new Date(), updatedAt: new Date(),
    });
    await setDoc(doc(db, 'users', OWNER_A, 'customers', 'cust1'), {
      name: 'أحمد', phone: '0100', address: null, notes: null,
      totalPurchases: 0, pendingAmount: 0, createdAt: new Date(),
    });
    await setDoc(doc(db, 'users', OWNER_A, 'sales', 'sale1'), saleDoc(EMP_A));

    await setDoc(doc(db, 'users', OWNER_B, 'inventory', 'invB'), {
      brand: 'Adidas', productName: 'Run', size: '43',
      openingBalance: 5, soldQuantity: 0, currentPrice: 200,
      createdAt: new Date(), updatedAt: new Date(),
    });
  });
});

const asOwnerA = () => testEnv.authenticatedContext(OWNER_A).firestore();
const asEmpA = () => testEnv.authenticatedContext(EMP_A).firestore();
const asOwnerB = () => testEnv.authenticatedContext(OWNER_B).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

// ─── The headline guarantee ──────────────────────────────────────────────────

describe('cross-tenant isolation', () => {
  it('owner B cannot read owner A inventory', async () => {
    await assertFails(getDoc(doc(asOwnerB(), 'users', OWNER_A, 'inventory', 'inv1')));
  });

  it('owner B cannot list owner A inventory', async () => {
    await assertFails(getDocs(collection(asOwnerB(), 'users', OWNER_A, 'inventory')));
  });

  it('owner B cannot read owner A sales or customers', async () => {
    await assertFails(getDoc(doc(asOwnerB(), 'users', OWNER_A, 'sales', 'sale1')));
    await assertFails(getDoc(doc(asOwnerB(), 'users', OWNER_A, 'customers', 'cust1')));
  });

  it('owner B cannot write into owner A tenant', async () => {
    await assertFails(setDoc(doc(asOwnerB(), 'users', OWNER_A, 'inventory', 'hack'), {
      brand: 'x', productName: 'x', size: '1', openingBalance: 1,
      soldQuantity: 0, currentPrice: 1, createdAt: new Date(), updatedAt: new Date(),
    }));
  });

  it('employee of tenant A cannot reach tenant B', async () => {
    await assertFails(getDoc(doc(asEmpA(), 'users', OWNER_B, 'inventory', 'invB')));
  });

  it('anonymous users are locked out entirely', async () => {
    await assertFails(getDoc(doc(asAnon(), 'users', OWNER_A, 'inventory', 'inv1')));
    await assertFails(getDoc(doc(asAnon(), 'users', OWNER_A)));
  });

  it('the legacy flat collections are unreachable', async () => {
    await assertFails(getDocs(collection(asOwnerA(), 'inventory')));
    await assertFails(getDocs(collection(asOwnerA(), 'sales')));
    await assertFails(getDocs(collection(asOwnerA(), 'customers')));
  });
});

// ─── Membership documents ────────────────────────────────────────────────────

describe('users / membership', () => {
  it('a new user may create their own owner document', async () => {
    const db = testEnv.authenticatedContext('newOwner').firestore();
    await assertSucceeds(setDoc(doc(db, 'users', 'newOwner'),
      userDoc('newOwner', 'newOwner', 'admin')));
  });

  it('a new user may NOT attach themselves to an existing tenant', async () => {
    const db = testEnv.authenticatedContext('intruder').firestore();
    await assertFails(setDoc(doc(db, 'users', 'intruder'),
      userDoc('intruder', OWNER_A, 'employee')));
    await assertFails(setDoc(doc(db, 'users', 'intruder'),
      userDoc('intruder', OWNER_A, 'admin')));
  });

  it('an admin may create an employee inside their own tenant', async () => {
    await assertSucceeds(setDoc(doc(asOwnerA(), 'users', 'newEmp'),
      userDoc('newEmp', OWNER_A, 'employee')));
  });

  it('an admin may NOT create a user inside another tenant', async () => {
    await assertFails(setDoc(doc(asOwnerA(), 'users', 'newEmp'),
      userDoc('newEmp', OWNER_B, 'employee')));
  });

  it('an employee may NOT create users at all', async () => {
    await assertFails(setDoc(doc(asEmpA(), 'users', 'newEmp'),
      userDoc('newEmp', OWNER_A, 'employee')));
  });

  it('an employee may not promote themselves to admin', async () => {
    await assertFails(updateDoc(doc(asEmpA(), 'users', EMP_A), { role: 'admin' }));
  });

  it('an employee may not reactivate themselves', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', EMP_A), { isActive: false });
    });
    await assertFails(updateDoc(doc(asEmpA(), 'users', EMP_A), { isActive: true }));
  });

  it('an employee may rename themselves', async () => {
    await assertSucceeds(updateDoc(doc(asEmpA(), 'users', EMP_A), { name: 'اسم جديد' }));
  });

  it('nobody may move a user to another tenant', async () => {
    await assertFails(updateDoc(doc(asOwnerA(), 'users', EMP_A), { ownerId: OWNER_B }));
    await assertFails(updateDoc(doc(asEmpA(), 'users', EMP_A), { ownerId: OWNER_B }));
  });

  it('an admin may deactivate an employee of their tenant', async () => {
    await assertSucceeds(updateDoc(doc(asOwnerA(), 'users', EMP_A), { isActive: false }));
  });

  it('an admin may NOT deactivate an admin of another tenant', async () => {
    await assertFails(updateDoc(doc(asOwnerA(), 'users', OWNER_B), { isActive: false }));
  });

  it('the tenant owner document cannot be modified by anyone else', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', 'admin2'),
        userDoc('admin2', OWNER_A, 'admin'));
    });
    const asAdmin2 = testEnv.authenticatedContext('admin2').firestore();
    await assertFails(updateDoc(doc(asAdmin2, 'users', OWNER_A), { isActive: false }));
  });

  it('membership documents can never be deleted', async () => {
    await assertFails(deleteDoc(doc(asOwnerA(), 'users', EMP_A)));
  });

  it('an unfiltered list of all users is rejected', async () => {
    await assertFails(getDocs(collection(asOwnerA(), 'users')));
  });

  it('a tenant-filtered list of users succeeds', async () => {
    const q = query(collection(asOwnerA(), 'users'),
                    where('ownerId', '==', OWNER_A), orderBy('name'));
    const snap = await assertSucceeds(getDocs(q));
    assert.strictEqual(snap.size, 2);
  });

  it('listing another tenant\'s users is rejected', async () => {
    const q = query(collection(asOwnerA(), 'users'), where('ownerId', '==', OWNER_B));
    await assertFails(getDocs(q));
  });
});

// ─── Roles within one tenant ─────────────────────────────────────────────────

describe('roles inside a tenant', () => {
  it('an employee may read inventory but not create it', async () => {
    await assertSucceeds(getDoc(doc(asEmpA(), 'users', OWNER_A, 'inventory', 'inv1')));
    await assertFails(setDoc(doc(asEmpA(), 'users', OWNER_A, 'inventory', 'inv2'), {
      brand: 'x', productName: 'x', size: '1', openingBalance: 1,
      soldQuantity: 0, currentPrice: 1, createdAt: new Date(), updatedAt: new Date(),
    }));
  });

  it('an employee may move stock (soldQuantity + updatedAt only)', async () => {
    await assertSucceeds(updateDoc(doc(asEmpA(), 'users', OWNER_A, 'inventory', 'inv1'),
      { soldQuantity: 3, updatedAt: new Date() }));
  });

  it('an employee may NOT re-price an item', async () => {
    await assertFails(updateDoc(doc(asEmpA(), 'users', OWNER_A, 'inventory', 'inv1'),
      { currentPrice: 1 }));
    await assertFails(updateDoc(doc(asEmpA(), 'users', OWNER_A, 'inventory', 'inv1'),
      { soldQuantity: 3, currentPrice: 1, updatedAt: new Date() }));
  });

  it('an employee may not delete inventory or customers', async () => {
    await assertFails(deleteDoc(doc(asEmpA(), 'users', OWNER_A, 'inventory', 'inv1')));
    await assertFails(deleteDoc(doc(asEmpA(), 'users', OWNER_A, 'customers', 'cust1')));
  });

  it('an admin may do all of the above', async () => {
    await assertSucceeds(updateDoc(doc(asOwnerA(), 'users', OWNER_A, 'inventory', 'inv1'),
      { currentPrice: 150 }));
    await assertSucceeds(deleteDoc(doc(asOwnerA(), 'users', OWNER_A, 'inventory', 'inv1')));
  });

  it('an employee may create a customer and update balances', async () => {
    await assertSucceeds(setDoc(doc(asEmpA(), 'users', OWNER_A, 'customers', 'cust2'), {
      name: 'عميل جديد', phone: '0111', address: null, notes: null,
      totalPurchases: 0, pendingAmount: 0, createdAt: new Date(),
    }));
    await assertSucceeds(updateDoc(doc(asEmpA(), 'users', OWNER_A, 'customers', 'cust1'),
      { totalPurchases: 100, pendingAmount: 0 }));
  });

  it('a deactivated employee loses all access', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', EMP_A), { isActive: false });
    });
    await assertFails(getDoc(doc(asEmpA(), 'users', OWNER_A, 'inventory', 'inv1')));
    await assertFails(getDocs(collection(asEmpA(), 'users', OWNER_A, 'sales')));
  });
});

// ─── Sales ───────────────────────────────────────────────────────────────────

describe('sales', () => {
  it('an employee may record a sale in their own name', async () => {
    await assertSucceeds(setDoc(doc(asEmpA(), 'users', OWNER_A, 'sales', 's2'),
      saleDoc(EMP_A)));
  });

  it('an employee may NOT record a sale in someone else\'s name', async () => {
    await assertFails(setDoc(doc(asEmpA(), 'users', OWNER_A, 'sales', 's3'),
      saleDoc(OWNER_A)));
  });

  it('an empty or negative invoice is rejected', async () => {
    await assertFails(setDoc(doc(asEmpA(), 'users', OWNER_A, 'sales', 's4'),
      saleDoc(EMP_A, { items: [] })));
    await assertFails(setDoc(doc(asEmpA(), 'users', OWNER_A, 'sales', 's5'),
      saleDoc(EMP_A, { totalAmount: -10 })));
    await assertFails(setDoc(doc(asEmpA(), 'users', OWNER_A, 'sales', 's6'),
      saleDoc(EMP_A, { status: 'whatever' })));
  });

  it('only an admin may change a sale status or delete a sale', async () => {
    await assertFails(updateDoc(doc(asEmpA(), 'users', OWNER_A, 'sales', 'sale1'),
      { status: 'returned' }));
    await assertFails(deleteDoc(doc(asEmpA(), 'users', OWNER_A, 'sales', 'sale1')));

    await assertSucceeds(updateDoc(doc(asOwnerA(), 'users', OWNER_A, 'sales', 'sale1'),
      { status: 'returned' }));
    await assertSucceeds(deleteDoc(doc(asOwnerA(), 'users', OWNER_A, 'sales', 'sale1')));
  });

  it('authorship of a sale is immutable', async () => {
    await assertFails(updateDoc(doc(asOwnerA(), 'users', OWNER_A, 'sales', 'sale1'),
      { createdById: OWNER_A }));
  });
});
