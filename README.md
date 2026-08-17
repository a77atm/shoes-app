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
- **Storage** → Get started

### 3. نشر قواعد الأمان

```bash
firebase deploy --only firestore:rules
firebase deploy --only storage
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
  "imageUrl": "string | null",
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
      "priceAtSale": 450.0,
      "imageUrl": "string | null"
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

أضف هذه الـ composite indexes في Firebase Console:

| Collection | Fields | Order |
|-----------|--------|-------|
| `sales` | `status` ASC, `saleDate` DESC | Composite |
| `sales` | `customerId` ASC, `saleDate` DESC | Composite |
| `sales` | `saleDate` ASC, `status` ASC | Composite |
| `inventory` | `brand` ASC, `productName` ASC | Composite |

---

## ✨ الميزات

| الميزة | الوصف |
|--------|-------|
| 🔐 Auth | تسجيل دخول + صلاحيات Admin/Employee |
| 📦 مخزون | Brand+Name+Size + صورة + رصيد + سعر |
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
