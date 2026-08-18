# Multi-Tenancy — Architecture, Rules & Deployment

هذا المستند يشرح تحويل التطبيق من نظام أحادي المستأجر (single-tenant) إلى نظام
متعدد المستأجرين (multi-tenant) مع عزل كامل لبيانات كل متجر.

---

## 1. The data model

```
users/{uid}                                    ← identity + membership document
  ownerId   : string   UID of the tenant this user belongs to
  role      : string   'admin' | 'employee'
  isActive  : bool
  name, email, storeName, createdAt

users/{ownerId}/inventory/{itemId}             ← tenant data
users/{ownerId}/customers/{customerId}
users/{ownerId}/sales/{saleId}
```

* **Store owner** signs up → `users/{uid}` with `ownerId == uid`, `role == 'admin'`.
  Their store's data lives under `users/{uid}/…`.
* **Employee** is created by that admin → `users/{empUid}` with
  `ownerId == the admin's ownerId`. The employee therefore reads and writes the
  **same** sub-collections as the admin — one shared store, two accounts.

### Why the membership document stays at the root

`users/{uid}` has to be reachable from a UID alone, because at sign-in the only
thing we know is `request.auth.uid`. If an employee's document lived at
`users/{ownerId}/members/{uid}` there would be no way to find it without already
knowing the tenant — a chicken-and-egg problem. So the root `users` collection
is the *directory* (UID → tenant), and everything else hangs off the owner's UID.

### Why nested sub-collections instead of a flat `ownerId` field

| | nested `users/{ownerId}/…` | flat + `ownerId` field |
|---|---|---|
| Isolation | property of the **path** | property of a **field** |
| A forgotten `.where()` | returns *nothing* (path is wrong) | returns **every tenant's data** |
| Security rule | `myOwnerId() == ownerId` from the wildcard | must validate the filter on every query |
| Indexes | tenant is not an index column | `ownerId` prepended to every composite index |
| Cross-tenant leak surface | collection-group queries only — and no rule grants them | any query that drops the filter |

The nested layout makes the dangerous mistake (forgetting to scope a query)
*fail closed*. That is the whole argument, and it is why it was the right call
here even though the flat model is also workable.

**The one thing to keep in mind:** collection-group queries (`collectionGroup('sales')`)
*would* span tenants. No rule in `firestore.rules` uses a recursive wildcard over
these sub-collections, so Firestore denies them by default. Don't add one.

### Trade-off accepted

A single tenant's data now lives under a single document path. Firestore has no
per-document-tree size limit, so this scales fine, but it does mean a tenant
cannot be "moved" cheaply — migrating a store to another owner means copying
documents. That is a deliberate trade: tenant moves are rare, forgotten query
filters are not.

---

## 2. How isolation is enforced, in three layers

1. **Path** — `TenantContext` (`lib/data/services/tenant_context.dart`) is the
   *only* place a Firestore reference is constructed. Every service takes a
   `TenantContext` in its constructor and reaches Firestore exclusively through
   `tenant.inventory` / `tenant.customers` / `tenant.sales`. There is no code
   path that can build an unscoped reference.

2. **Providers** — `tenantProvider` throws if there is no resolved membership
   document, so a service can never be constructed without a tenant. Every data
   provider sits below it, which means signing out or switching accounts tears
   down and rebuilds every stream. No stale data from the previous store
   survives.

3. **Rules** — `firestore.rules` re-derives the caller's tenant server-side from
   `users/{request.auth.uid}.ownerId` and compares it to the `{ownerId}` in the
   path. The client is never trusted.

---

## 3. Role matrix (within one tenant)

|            | read | create | update | delete |
|------------|------|--------|--------|--------|
| inventory — admin | ✓ | ✓ | ✓ | ✓ |
| inventory — employee | ✓ | ✗ | `soldQuantity` + `updatedAt` only | ✗ |
| customers — admin | ✓ | ✓ | ✓ | ✓ |
| customers — employee | ✓ | ✓ | ✓ | ✗ |
| sales — admin | ✓ | ✓ | ✓ | ✓ |
| sales — employee | ✓ | ✓ (own name only) | ✗ | ✗ |
| users — admin | own tenant | employees of own tenant | own tenant, not the owner doc | ✗ |
| users — employee | own tenant | ✗ | own `name` only | ✗ |

The `soldQuantity` carve-out matters: recording a sale moves stock, so an
employee *must* be able to touch inventory. `affectedKeys().hasOnly([...])`
makes that the only field they can change — they cannot re-price an item.

---

## 4. Bugs fixed along the way

These were pre-existing issues that multi-tenancy made unavoidable to address:

1. **Creating an employee signed the admin out.**
   `createUserWithEmailAndPassword` signs the new user in on the instance it is
   called on. `AuthService.createEmployee` now uses a *secondary* `FirebaseApp`
   (reusing the primary app's options) and signs it out immediately, leaving the
   admin's session intact.

2. **Employees could not record sales at all.** The old rules let only admins
   update `inventory`, but the sales transaction increments `soldQuantity` — so
   every employee sale failed with `permission-denied`.

3. **The sales "transaction" did no reads.** It wrote blindly, so it never
   actually protected anything. `addSale` now reads the customer and every
   referenced inventory item inside the transaction and validates available
   stock before writing — two people selling the last pair can no longer both
   succeed.

4. **Returns were not atomic.** Stock was reverted in a separate pass *after*
   the transaction committed. Everything is now in one commit.

5. **Deleting a sale left phantom revenue.** `deleteSale` now unwinds the
   customer totals and the stock in the same transaction.

6. **`where('status', isNotEqualTo: 'returned')` + a `saleDate` range** forces
   Firestore to order by `status` first and is awkward to index. Replaced with
   `whereIn: ['paid', 'pending']`.

7. **Report double-counting.** Customer revenue was aggregated inside the
   per-item loop, so a 3-line invoice counted the customer 3 times.

---

## 5. Migration

**This is a breaking change — a fresh start.** The old flat `/inventory`,
`/customers` and `/sales` collections are no longer readable by any client (no
rule matches them), and the app never looks at them again. They are left in
place, untouched; delete them from the console once you're satisfied.

Existing `users/{uid}` documents keep working: `UserModel.fromMap` falls back to
`ownerId = uid` when the field is missing, so an existing admin account becomes
the owner of its own (empty) tenant on first sign-in. **Existing *employee*
accounts must be fixed manually** — otherwise each one becomes its own separate
tenant. For each employee, set `ownerId` to the admin's UID in the console.

If you later decide you do want the old data, the copy is mechanical — for a
target owner UID, read each flat collection and re-write each document to
`users/{ownerId}/{collection}/{docId}` with the Admin SDK. Say the word and
I'll write that script.

---

## 6. Deployment

### 6.1 Deploy the rules and indexes

```bash
# from the repo root
npm install -g firebase-tools      # if you don't have it
firebase login
firebase use shoesapp-e64be        # already set in .firebaserc

# indexes FIRST — they take minutes to build, and queries fail until they exist
firebase deploy --only firestore:indexes

# watch until every index shows "Enabled"
#   https://console.firebase.google.com/project/shoesapp-e64be/firestore/indexes

# then the rules
firebase deploy --only firestore:rules
```

Deploying indexes first matters: if the rules go out first, the app will be
allowed to run queries whose indexes don't exist yet and you'll see
`FAILED_PRECONDITION` errors with a "create index" link.

### 6.2 Required indexes

All ten are already in `firestore.indexes.json`. `queryScope: "COLLECTION"` on a
sub-collection name applies to every `users/{ownerId}/…` instance of it.

| Collection | Fields | Used by |
|---|---|---|
| `users` | `ownerId` ASC, `name` ASC | admin listing tenant members |
| `inventory` | `brand` ASC, `productName` ASC | inventory list |
| `sales` | `status` ASC, `saleDate` ASC | reports + dashboard |
| `sales` | `status` ASC, `saleDate` DESC | filter by status |
| `sales` | `customerId` ASC, `saleDate` DESC | customer detail |
| `sales` | `saleType` ASC, `saleDate` DESC | filter by type |
| `sales` | `status`, `customerId`, `saleDate` DESC | combined filters |
| `sales` | `status`, `saleType`, `saleDate` DESC | combined filters |
| `sales` | `customerId`, `saleType`, `saleDate` DESC | combined filters |
| `sales` | `status`, `customerId`, `saleType`, `saleDate` DESC | all filters |

Single-field indexes (`saleDate`, `pendingAmount`, `name`, `status`) are created
automatically by Firestore — nothing to do.

**Optional cost saving:** the `items` array on a sale is auto-indexed and nothing
queries it. You can add a `fieldOverride` disabling indexing on `sales.items` to
cut write costs on large invoices. Left out by default so nothing surprises you.

### 6.3 Test the rules before deploying

```bash
cd test/firestore_rules
npm install
npm test
```

This boots the Firestore emulator and runs ~30 assertions covering cross-tenant
reads, cross-tenant writes, privilege escalation, tenant hopping via `ownerId`,
deactivated accounts and the employee/admin split. Run it before every rules
change.

### 6.4 Firebase Console checklist

* **Authentication → Sign-in method → Email/Password**: enabled. Self sign-up now
  goes through the app, so leave it on.
* Optionally enable **email enumeration protection**.
* Consider a **Blocking function** (`beforeCreate`) if you later want to restrict
  who can register a new store.

---

## 7. Files changed

| File | Change |
|---|---|
| `lib/data/services/tenant_context.dart` | **new** — the only place Firestore refs are built |
| `lib/data/services/auth_service.dart` | `signUp`, `createEmployee` (secondary app), `watchUserData`, `getTenantUsers` |
| `lib/data/services/inventory_service.dart` | tenant-scoped; admin guards |
| `lib/data/services/customer_service.dart` | tenant-scoped |
| `lib/data/services/sales_service.dart` | tenant-scoped; real transactions; `whereIn` statuses; report fix |
| `lib/data/models/models.dart` | `UserModel.ownerId`, `storeName`, `isOwner`, `toEditableMap` |
| `lib/presentation/providers/providers.dart` | tenant-scoped provider graph |
| `lib/presentation/screens/auth/signup_screen.dart` | **new** — store owner self-registration |
| `lib/presentation/screens/auth/login_screen.dart` | link to sign-up |
| `lib/presentation/screens/users/users_screen.dart` | `createEmployee` with inherited `ownerId`; owner protected |
| `lib/presentation/screens/sales/add_sale_screen.dart` | author stamped server-side |
| `lib/presentation/screens/sales/sale_detail_screen.dart` | new `updateSaleStatus` signature + error handling |
| `lib/core/utils/router.dart` | `/signup` route |
| `lib/core/constants/app_constants.dart` | structure docs + Arabic strings |
| `firestore.rules` | full rewrite |
| `firestore.indexes.json` | rewritten for the scoped queries |
| `firebase.json` | emulator config for rules tests |
| `test/firestore_rules/` | **new** — rules test suite |

---

## 8. Manual smoke test after deploying

1. Sign up as owner A → add an inventory item, a customer, a sale.
2. Sign out, sign up as owner B → the dashboard is **empty**. Owner B's inventory,
   customers and sales are all their own.
3. As owner A, create an employee → **you stay signed in** as the admin.
4. Sign in as that employee → they see owner A's data, can record a sale, but the
   "add inventory" button and the Users screen are refused.
5. As owner A, deactivate the employee → the employee's app loses access
   immediately, without a restart.
