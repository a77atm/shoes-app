#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# نشر Firestore rules + indexes من الريبو
#
# بيتنفذ من الـ CI (Codemagic / GitHub Actions) قبل عملية الـ build.
#
# مهم: الكود بيقرا ويكتب تحت users/{ownerId}/inventory|sales|customers
# فلو الـ rules اللي على السيرفر لسه القديمة (الـ collections الجذرية) هتاخد
# permission-denied على كل حاجة. عشان كده السكريبت ده بينشر الـ rules كمان
# مش الـ indexes بس.
#
# المتغيرات المطلوبة:
#   FIREBASE_TOKEN            توكن من `firebase login:ci`   (الطريقة الأبسط)
#   أو
#   GOOGLE_APPLICATION_CREDENTIALS  مسار ملف service-account JSON
#
# متغير اختياري:
#   FIREBASE_PROJECT_ID       افتراضيًا shoesapp-e64be
# ---------------------------------------------------------------------------
set -euo pipefail

PROJECT_ID="${FIREBASE_PROJECT_ID:-shoesapp-e64be}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Firestore deploy | project: $PROJECT_ID"

TARGETS=()

if [ -f firestore.indexes.json ]; then
  # تحقق مبدئي إن الـ JSON سليم قبل ما نبعته لـ Firebase
  node -e "JSON.parse(require('fs').readFileSync('firestore.indexes.json','utf8'))" \
    || { echo "!! firestore.indexes.json مش JSON صحيح"; exit 1; }
  TARGETS+=("firestore:indexes")
else
  echo "!! firestore.indexes.json غير موجود — تم تخطي الفهارس"
fi

if [ -f firestore.rules ]; then
  TARGETS+=("firestore:rules")
else
  echo "!! firestore.rules غير موجود — تم تخطي القواعد"
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "!! مفيش حاجة تتنشر — تم التخطي"
  exit 0
fi

# تأكد إن firebase-tools متثبت
if ! command -v firebase >/dev/null 2>&1; then
  echo "==> تثبيت firebase-tools"
  npm install -g firebase-tools
fi

AUTH_ARGS=()
if [ -n "${FIREBASE_TOKEN:-}" ]; then
  AUTH_ARGS+=(--token "$FIREBASE_TOKEN")
elif [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
  echo "==> استخدام service account credentials"
else
  echo "!! مفيش FIREBASE_TOKEN ولا GOOGLE_APPLICATION_CREDENTIALS — تم تخطي النشر"
  echo "   (الـ build هيكمل عادي، بس لازم تنشر الـ rules والـ indexes يدويًا)"
  exit 0
fi

ONLY="$(IFS=, ; echo "${TARGETS[*]}")"

# ${arr[@]+"${arr[@]}"} عشان set -u ما يقعش لو المصفوفة فاضية
firebase use "$PROJECT_ID" ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} || true
firebase deploy \
  --only "$ONLY" \
  --project "$PROJECT_ID" \
  --non-interactive \
  --force \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

echo "==> تم النشر بنجاح ✅ ($ONLY)"
echo "   ملاحظة: Firestore بياخد وقت (دقائق) عشان يبني الـ index بحالة Building → Enabled"
echo "   لو استعلام فشل بـ failed-precondition، ده معناه إن الـ index لسه بيتبني."
