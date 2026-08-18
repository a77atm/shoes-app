# 👟 Shoe Store — نظام إدارة محل الأحذية

تطبيق Flutter كامل لإدارة المخزون والمبيعات مع Firebase كـ backend.

---

## 🏗️ هيكل المشروع

```
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart       # الثوابت والنصوص
│   ├── theme/
│   │   └── app_theme.dart           # Material 3 + Light/Dark
│   ├── utils/
│   │   └── router.dart              # GoRouter navigation
│   └── widgets/
│       └── main_scaffold.dart       # Bottom nav + shell
│
├── data/
│   ├── models/
│   │   └── models.dart              # UserModel, InventoryModel, SaleModel, CustomerModel
│   └── services/
│       ├── auth_service.dart        # Firebase Auth
│       ├── inventory_service.dart   # Firestore CRUD للمخزون
│       ├── sales_service.dart       # Firestore CRUD للمبيعات + تقارير
│       └── customer_service.dart    # Firestore CRUD للعملاء
│
├── presentation/
│   ├── providers/
│   │   └── providers.dart           # Riverpod providers + CartNotifier
│   └── screens/
│       ├── auth/login_screen.dart
│       ├── dashboard/dashboard_screen.dart
│       ├── inventory/
│       │   ├── inventory_screen.dart
│       │   └── add_edit_inventory_screen.dart
│       ├── sales/
│       │   ├── sales_screen.dart
│       │   ├── add_sale_screen.dart
│       │   └── sale_detail_screen.dart
│       ├── customers/
│       │   ├── customers_screen.dart
│       │   └── customer_detail_screen.dart
│       ├── reports/reports_screen.dart
│       └── users/users_screen.dart
│
└── main.dart
```

---

## ⚙️ الإعداد

### 1. إنشاء مشروع Firebase

```bash
# تثبيت Firebase CLI
npm install -g firebase-tools
firebase login

# ربط المشروع
flutterfire configure
```

هذا ينشئ ملف `lib/firebase_options.dart` تلقائياً.

### 2. تفعيل Firebase Services

في Firebase Console:
- **Authentication** → Sign-in method → Email/Password ✓
- **Cloud Firestore** → Create database (Production mode)

### 3. نشر قواعد الأمان

```bash
firebase deploy --only firestore:rules
```

### 4. إضافة أول مستخدم (Admin)

في Firebase Console → Authentication → Add user:
- Email: admin@store.com
- Password: Admin@123

ثم في Firestore → Collection `users` → Add document بنفس الـ UID:
```json
{
  "name": "المدير",
  "email": "admin@store.com",
  "role": "admin",
  "isActive": true,
  "createdAt": "<timestamp>"
}
```

### 5. إضافة Localization

```bash
flutter pub add flutter_localizations --sdk=flutter
flutter pub add intl
```

في `main.dart` أضف:
```dart
import 'package:flutter_localizations/flutter_localizations.dart';

localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

### 6. تشغيل المشروع

```bash
flutter pub get
flutter run
```

---

## 🗄️ هيكل Firestore

### `users/{uid}`
```json
{
  "name": "string",
  "email": "string",
  "role": "admin | employee",
  "isActive": true,
  "createdAt": "timestamp"
}
```

### `inventory/{id}`
```json
{
  "brand": "string",
  "productName": "string",
  "size": "string",
  "openingBalance": 50,
  "soldQuantity": 12,
  "currentPrice": 450.0,
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

### `sales/{id}`
```json
{
  "customerId": "string",
  "customerName": "string",
  "items": [
    {
      "inventoryId": "string",
      "brand": "string",
      "productName": "string",
      "size": "string",
      "quantity": 2,
      "priceAtSale": 450.0
    }
  ],
  "totalAmount": 900.0,
  "status": "paid | pending | returned",
  "saleType": "normal | bulk",
  "notes": "string | null",
  "createdById": "string",
  "createdByName": "string",
  "saleDate": "timestamp",
  "createdAt": "timestamp"
}
```

### `customers/{id}`
```json
{
  "name": "string",
  "phone": "string",
  "address": "string | null",
  "notes": "string | null",
  "totalPurchases": 2500.0,
  "pendingAmount": 450.0,
  "createdAt": "timestamp"
}
```

---

## 📋 Firestore Indexes المطلوبة

> ⚙️ **النشر بقى تلقائي — مش خطوة يدوية.**
> مصدر الحقيقة الوحيد هو ملف [`firestore.indexes.json`](firestore.indexes.json)،
> وبيتنشر أوتوماتيك على مشروع `shoesapp-e64be` عن طريق:
> - **Codemagic** — خطوة `Deploy Firestore indexes` بتشتغل قبل الـ build في كل الـ workflows.
> - **GitHub Actions** — workflow [`.github/workflows/firestore-indexes.yml`](.github/workflows/firestore-indexes.yml)
>   بيشتغل على كل push لـ `main` بيلمس `firestore.indexes.json`.
>
> الاتنين بينفذوا نفس السكريبت: [`scripts/deploy_firestore_indexes.sh`](scripts/deploy_firestore_indexes.sh)
> → `firebase deploy --only firestore:indexes`.
>
> **المطلوب مرة واحدة بس:** تحط `FIREBASE_TOKEN` (من `firebase login:ci`) في:
> Codemagic → Environment variables → group اسمه `firebase`،
> و GitHub → Settings → Secrets and variables → Actions → `FIREBASE_TOKEN`.

### الـ Composite Indexes الموجودة فعلاً في `firestore.indexes.json`

| # | Collection | Fields (بالترتيب) | الكويري اللي محتاجاها |
|---|-----------|-------------------|------------------------|
| 1 | `inventory` | `brand` ASC, `productName` ASC | `InventoryService.getInventoryStream()` — `orderBy('brand').orderBy('productName')` |
| 2 | `sales` | `status` ASC, `saleDate` DESC | `SalesService.getSalesStream()` — فلتر الحالة + ترتيب بالتاريخ |
| 3 | `sales` | `customerId` ASC, `saleDate` DESC | `getSalesStream()` — مبيعات عميل معيّن |
| 4 | `sales` | `saleType` ASC, `saleDate` DESC | `getSalesStream()` — فلتر نوع البيع (عادي/مجمع) |
| 5 | `sales` | `status` ASC, `customerId` ASC, `saleDate` DESC | `getSalesStream()` — حالة + عميل مع بعض |
| 6 | `sales` | `status` ASC, `saleType` ASC, `saleDate` DESC | `getSalesStream()` — حالة + نوع البيع مع بعض |
| 7 | `sales` | `customerId` ASC, `saleType` ASC, `saleDate` DESC | `getSalesStream()` — عميل + نوع البيع مع بعض |
| 8 | `sales` | `status` ASC, `customerId` ASC, `saleType` ASC, `saleDate` DESC | `getSalesStream()` — الفلاتر التلاتة مع بعض |
| 9 | `sales` | `saleDate` ASC, `status` ASC | `getSalesReport()` و `getDashboardStats()` — نطاق تاريخ + `status != returned` |
| 10 | `sales` | `status` ASC, `saleDate` ASC | نفس الكويري السابقة (الترتيب البديل اللي ممكن يختاره الـ query planner) |

**ملاحظات:**

- فلاتر التاريخ (`startDate` / `endDate`) في شاشة المبيعات بتشتغل على نفس حقل `saleDate`
  اللي بيتم الترتيب بيه، فمش محتاجة index زيادة فوق اللي فوق.
- الكويريز دي **مش** محتاجة composite index (بيكفيها الـ single-field index التلقائي):
  - `customers` — `orderBy('name')`
  - `customers` — `where('pendingAmount' > 0).orderBy('pendingAmount', desc)` (نفس الحقل)
  - `users` — `orderBy('name')`
  - `sales` — `where('status' == pending)` لوحدها
  - `inventory` — قراءة كل الـ collection من غير ترتيب (`getLowStockStream`)
- بعد أي نشر، Firestore بياخد دقايق عشان الـ index يعدّي من **Building** لـ **Enabled**.
  لحد ما يخلّص، الكويري ممكن تفضل ترمي `failed-precondition`.
- **لو ضفت فلتر أو `orderBy` جديد في الكود:** ضيف الـ index المقابل في
  `firestore.indexes.json` وبس — الـ CI هينشره لوحده.

### نشر يدوي (لو محتاج)

```bash
firebase login
firebase use shoesapp-e64be
firebase deploy --only firestore:indexes
```

---

## ✨ الميزات

| الميزة | الوصف |
|--------|-------|
| 🔐 Auth | تسجيل دخول + صلاحيات Admin/Employee |
| 📦 مخزون | Brand+Name+Size + رصيد + سعر (بدون صور) |
| 💰 مبيعات | عادية/مجمعة + سعر وقت البيع + حالات |
| 🔍 بحث وفلاتر | بحث + فلتر تاريخ/حالة/نوع/سعر |
| 📊 تقارير | يومي/أسبوعي/شهري + مخطط الإيرادات |
| 👥 عملاء | بيانات + سجل مبيعات + مستحقات |
| 🔔 تنبيهات | تنبيه مخزون منخفض في الـ Dashboard |
| 🌙 Dark Mode | دعم كامل للوضعين الفاتح والداكن |

---

## 📱 Screens

- **Login** — تسجيل دخول مع validation
- **Dashboard** — إحصائيات يومية/شهرية + تنبيهات مخزون + إجراءات سريعة
- **Inventory** — Grid/List view + search + CRUD كامل
- **Sales** — قائمة مع filters + إضافة بيع مع cart
- **Sale Detail** — تفاصيل + تغيير حالة
- **Customers** — كل العملاء + تبويب المستحقات
- **Customer Detail** — بيانات + سجل مبيعات
- **Reports** — تقارير بفترات مختلفة + رسم بياني + top products/customers
- **Users** — إدارة المستخدمين (Admin فقط)
