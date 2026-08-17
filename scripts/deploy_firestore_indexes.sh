#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# نشر Firestore indexes تلقائيًا من firestore.indexes.json
#
# بيتنفذ من الـ CI (Codemagic / GitHub Actions) قبل عملية الـ build.
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

echo "==> Firestore indexes deploy | project: $PROJECT_ID"

if [ ! -f firestore.indexes.json ]; then
  echo "!! firestore.indexes.json غير موجود — تم التخطي"
  exit 0
fi

# تحقق مبدئي إن الـ JSON سليم قبل ما نبعته لـ Firebase
node -e "JSON.parse(require('fs').readFileSync('firestore.indexes.json','utf8'))" \
  || { echo "!! firestore.indexes.json مش JSON صحيح"; exit 1; }

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
  echo "!! مفيش FIREBASE_TOKEN ولا GOOGLE_APPLICATION_CREDENTIALS — تم تخطي نشر الـ indexes"
  echo "   (الـ build هيكمل عادي، بس لازم تنشر الـ indexes يدويًا)"
  exit 0
fi

firebase use "$PROJECT_ID" "${AUTH_ARGS[@]}" || true
firebase deploy \
  --only firestore:indexes \
  --project "$PROJECT_ID" \
  --non-interactive \
  --force \
  "${AUTH_ARGS[@]}"

echo "==> تم نشر الـ indexes بنجاح ✅"
echo "   ملاحظة: Firestore بياخد وقت (دقائق) عشان يبني الـ index بحالة Building → Enabled"
