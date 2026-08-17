#!/usr/bin/env node
/**
 * ---------------------------------------------------------------------------
 * سكريبت تنظيف: بيمسح حقل imageUrl من كل دوكومنتات Firestore
 *
 *   - inventory/{id}.imageUrl
 *   - sales/{id}.items[].imageUrl   (بيعيد كتابة مصفوفة items من غير الحقل)
 *
 * ⚠️  ده حذف دائم للداتا ومش بيترجع. اعمل Export للـ Firestore الأول:
 *     gcloud firestore export gs://<BUCKET>/backup-$(date +%F) \
 *       --project shoesapp-e64be
 *
 * الاستخدام:
 *   npm install firebase-admin
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *
 *   node scripts/remove_image_urls.js            # dry-run (بيعرض بس)
 *   node scripts/remove_image_urls.js --apply    # ينفّذ الحذف فعليًا
 * ---------------------------------------------------------------------------
 */

const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "shoesapp-e64be";
const BATCH_SIZE = 400;

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function commitAll(ops) {
  for (let i = 0; i < ops.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + BATCH_SIZE)) op(batch);
    await batch.commit();
    console.log(`   ✓ committed ${Math.min(i + BATCH_SIZE, ops.length)}/${ops.length}`);
  }
}

async function cleanInventory() {
  const snap = await db.collection("inventory").get();
  const ops = [];
  for (const doc of snap.docs) {
    if (Object.prototype.hasOwnProperty.call(doc.data(), "imageUrl")) {
      ops.push((b) =>
        b.update(doc.ref, { imageUrl: admin.firestore.FieldValue.delete() })
      );
    }
  }
  console.log(`inventory: ${ops.length} / ${snap.size} doc(s) فيهم imageUrl`);
  if (APPLY && ops.length) await commitAll(ops);
}

async function cleanSales() {
  const snap = await db.collection("sales").get();
  const ops = [];
  for (const doc of snap.docs) {
    const items = doc.data().items;
    if (!Array.isArray(items)) continue;
    if (!items.some((it) => it && Object.prototype.hasOwnProperty.call(it, "imageUrl")))
      continue;
    const cleaned = items.map(({ imageUrl, ...rest }) => rest);
    ops.push((b) => b.update(doc.ref, { items: cleaned }));
  }
  console.log(`sales: ${ops.length} / ${snap.size} doc(s) فيهم items[].imageUrl`);
  if (APPLY && ops.length) await commitAll(ops);
}

(async () => {
  console.log(`project: ${PROJECT_ID} | mode: ${APPLY ? "APPLY (حذف فعلي)" : "DRY-RUN"}\n`);
  await cleanInventory();
  await cleanSales();
  if (!APPLY) console.log("\nمفيش حاجة اتغيرت. شغّله بـ --apply عشان ينفّذ.");
  else console.log("\nتم ✅");
  process.exit(0);
})().catch((e) => {
  console.error("فشل:", e.message);
  process.exit(1);
});
