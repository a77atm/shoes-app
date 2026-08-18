#!/usr/bin/env node
/**
 * Shoe Store — migrate flat collections into the multi-tenant layout.
 *
 *   /inventory/{id}   ->  users/{OWNER_ID}/inventory/{id}
 *   /customers/{id}   ->  users/{OWNER_ID}/customers/{id}
 *   /sales/{id}       ->  users/{OWNER_ID}/sales/{id}
 *
 * Document IDs are preserved. That is not cosmetic: sales documents reference
 * customers by `customerId` and inventory by `items[].inventoryId`, so keeping
 * the IDs is what keeps those references valid after the move.
 *
 * The script is:
 *   - DRY RUN by default. Nothing is written unless you pass --commit.
 *   - Idempotent. Re-running overwrites the same destination docs, so a partial
 *     run can simply be repeated.
 *   - Non-destructive. The original flat collections are never modified or
 *     deleted. Delete them yourself from the console once you are satisfied.
 *
 * Usage:
 *   node migrate.js                 # dry run  — shows exactly what would move
 *   node migrate.js --commit        # perform the migration
 *   node migrate.js --verify        # compare source and destination counts
 */

const admin = require('firebase-admin');
const path = require('path');

// ─── Configuration ───────────────────────────────────────────────────────────

/** UID of the store owner who will own the migrated data. */
const OWNER_ID = 'jplpOBmdT1csFkwlw6T8GIFMvqw1'; // test@shoes.com

/** Path to the service account key you downloaded from the Firebase console. */
const SERVICE_ACCOUNT = path.join(__dirname, 'serviceAccountKey.json');

const COLLECTIONS = ['inventory', 'customers', 'sales'];

/** Firestore caps a batch at 500 writes. */
const BATCH_SIZE = 400;

// ─── Setup ───────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const COMMIT = args.includes('--commit');
const VERIFY_ONLY = args.includes('--verify');

let serviceAccount;
try {
  serviceAccount = require(SERVICE_ACCOUNT);
} catch (e) {
  console.error(`\n✖ Could not read ${SERVICE_ACCOUNT}`);
  console.error('  Download it from the Firebase console:');
  console.error('  Project settings → Service accounts → Generate new private key');
  console.error('  Save it next to this script as serviceAccountKey.json\n');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const tenantRoot = db.collection('users').doc(OWNER_ID);

// ─── Helpers ─────────────────────────────────────────────────────────────────

function banner() {
  console.log('');
  console.log('══════════════════════════════════════════════════════════════');
  console.log('  Shoe Store — multi-tenancy migration');
  console.log(`  Project : ${serviceAccount.project_id}`);
  console.log(`  Owner   : ${OWNER_ID}`);
  console.log(`  Mode    : ${VERIFY_ONLY ? 'VERIFY' : COMMIT ? 'COMMIT (writes!)' : 'DRY RUN (no writes)'}`);
  console.log('══════════════════════════════════════════════════════════════');
  console.log('');
}

/** Refuses to run if the owner's membership document is not set up correctly. */
async function checkOwner() {
  const snap = await tenantRoot.get();
  if (!snap.exists) {
    throw new Error(
      `users/${OWNER_ID} does not exist. Create the owner's membership ` +
      `document before migrating.`
    );
  }
  const data = snap.data();
  if (data.ownerId !== OWNER_ID) {
    throw new Error(
      `users/${OWNER_ID}.ownerId is "${data.ownerId}", expected "${OWNER_ID}". ` +
      `The target must be a tenant owner, not an employee.`
    );
  }
  console.log(`✔ Owner verified: ${data.name || '(no name)'} <${data.email || '?'}>\n`);
}

async function migrateCollection(name) {
  const sourceSnap = await db.collection(name).get();
  const destSnap = await tenantRoot.collection(name).get();

  const existing = new Set(destSnap.docs.map((d) => d.id));
  console.log(`── ${name}`);
  console.log(`   source      : ${sourceSnap.size} document(s)`);
  console.log(`   destination : ${destSnap.size} document(s) already present`);

  if (sourceSnap.empty) {
    console.log('   nothing to do\n');
    return { moved: 0, overwritten: 0 };
  }

  let moved = 0;
  let overwritten = 0;
  let batch = db.batch();
  let opsInBatch = 0;

  for (const doc of sourceSnap.docs) {
    const willOverwrite = existing.has(doc.id);
    if (willOverwrite) overwritten++;
    moved++;

    if (!COMMIT) {
      console.log(
        `   ${willOverwrite ? 'overwrite' : 'create   '} ${name}/${doc.id}`
      );
      continue;
    }

    batch.set(tenantRoot.collection(name).doc(doc.id), doc.data());
    opsInBatch++;

    if (opsInBatch >= BATCH_SIZE) {
      await batch.commit();
      console.log(`   committed ${opsInBatch} writes`);
      batch = db.batch();
      opsInBatch = 0;
    }
  }

  if (COMMIT && opsInBatch > 0) {
    await batch.commit();
    console.log(`   committed ${opsInBatch} writes`);
  }

  console.log(
    `   ${COMMIT ? 'migrated' : 'would migrate'} ${moved} document(s)` +
    (overwritten ? ` (${overwritten} overwriting existing)` : '') + '\n'
  );
  return { moved, overwritten };
}

async function verify() {
  let allMatch = true;
  for (const name of COLLECTIONS) {
    const src = await db.collection(name).get();
    const dst = await tenantRoot.collection(name).get();

    const srcIds = new Set(src.docs.map((d) => d.id));
    const dstIds = new Set(dst.docs.map((d) => d.id));
    const missing = [...srcIds].filter((id) => !dstIds.has(id));

    const ok = missing.length === 0;
    allMatch = allMatch && ok;

    console.log(`── ${name}`);
    console.log(`   source ${src.size}  →  destination ${dst.size}   ${ok ? '✔' : '✖'}`);
    if (!ok) console.log(`   missing: ${missing.join(', ')}`);
    console.log('');
  }
  return allMatch;
}

// ─── Main ────────────────────────────────────────────────────────────────────

(async () => {
  banner();

  try {
    await checkOwner();

    if (VERIFY_ONLY) {
      const ok = await verify();
      console.log(ok
        ? '✔ Every source document exists under the tenant.\n'
        : '✖ Some documents are missing. Re-run with --commit.\n');
      process.exit(ok ? 0 : 1);
    }

    let total = 0;
    for (const name of COLLECTIONS) {
      const { moved } = await migrateCollection(name);
      total += moved;
    }

    if (COMMIT) {
      console.log(`✔ Migration complete — ${total} document(s) written.`);
      console.log('  The original flat collections were NOT touched.');
      console.log('  Run `node migrate.js --verify` to double-check, then delete');
      console.log('  the old /inventory, /customers and /sales from the console.\n');
    } else {
      console.log(`Dry run finished — ${total} document(s) would be migrated.`);
      console.log('Nothing was written. Re-run with --commit to apply:\n');
      console.log('    node migrate.js --commit\n');
    }
    process.exit(0);
  } catch (err) {
    console.error(`\n✖ ${err.message}\n`);
    process.exit(1);
  }
})();
