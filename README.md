# ترحيل الداتا للنظام متعدد المستأجرين

بينقل الداتا الموجودة من المجموعات المسطّحة إلى متجر `test@shoes.com`:

```
/inventory/{id}   →   users/jplpOBmdT1csFkwlw6T8GIFMvqw1/inventory/{id}
/customers/{id}   →   users/jplpOBmdT1csFkwlw6T8GIFMvqw1/customers/{id}
/sales/{id}       →   users/jplpOBmdT1csFkwlw6T8GIFMvqw1/sales/{id}
```

**الـ IDs بتتحافظ عليها كما هي.** دي مش تفصيلة شكلية — الفواتير بتشاور على العملاء
بـ `customerId` وعلى المخزون بـ `items[].inventoryId`، فالحفاظ على الـ IDs هو اللي
بيخلي الروابط دي شغالة بعد النقل.

السكربت **مبيمسحش حاجة**. المجموعات القديمة بتفضل مكانها زي ما هي.

---

## الخطوات

### 1. ركّب Node.js

لو مش مركّب: <https://nodejs.org> → حمّل نسخة LTS.

للتأكد إنه اتركّب، افتح PowerShell واكتب:

```powershell
node --version
```

### 2. نزّل مفتاح حساب الخدمة

من Firebase Console:

**Project settings** (الترس جنب Project Overview) → تبويب **Service accounts** →
زرار **Generate new private key** → **Generate key**.

هينزّل ملف JSON. غيّر اسمه لـ `serviceAccountKey.json` وحطه **في نفس الفولدر ده**
جنب `migrate.js`.

> ⚠️ الملف ده مفتاح كامل الصلاحيات على المشروع. متحطهوش في Git ومتبعتهوش لحد.
> امسحه بعد ما تخلص الترحيل.

### 3. ركّب المكتبة

```powershell
cd "$env:USERPROFILE\Desktop\shoes-migration"
npm install firebase-admin
```

### 4. جرّب الأول من غير كتابة (dry run)

```powershell
node migrate.js
```

هيطبعلك كل مستند هيتنقل من غير ما يكتب أي حاجة. راجع الأرقام:
المفروض **3 مخزون، 2 عملاء، 7 مبيعات**.

### 5. نفّذ الترحيل

```powershell
node migrate.js --commit
```

### 6. تأكّد

```powershell
node migrate.js --verify
```

لازم يقول `✔` لكل مجموعة.

---

## بعد كده

- افتح الكونسول وشوف `users/jplpOBmdT1csFkwlw6T8GIFMvqw1` — هتلاقي تحتيها
  `inventory` و `customers` و `sales`.
- المجموعات القديمة `/inventory` و `/customers` و `/sales` لسه مكانها. امسحها
  بنفسك من الكونسول بعد ما تتأكد إن التطبيق الجديد شغال.
- امسح `serviceAccountKey.json`.

## لو حصل خطأ

| الرسالة | السبب |
|---|---|
| `Could not read serviceAccountKey.json` | المفتاح مش موجود أو اسمه غلط |
| `users/... does not exist` | وثيقة المالك مش موجودة |
| `ownerId is "..." expected "..."` | الحساب المستهدف موظف مش مالك |
| `PERMISSION_DENIED` | المفتاح من مشروع تاني |

السكربت idempotent — لو وقف في النص، شغّله تاني عادي.
