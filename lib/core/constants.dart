enum ChatMode { expense, income }

class AppConstants {
  static const String modelPath = 'assets/models/model-unsloth21.Q4_0.gguf';

  // 🔴 EXPENSE PROMPT (Extract Item, Qty, Price, Category)
  static const String kExpenseSystemPrompt = """<|im_start|>system
หน้าที่ของคุณคือแยกข้อมูลรายจ่ายเป็น JSON: item, qty, unit_price, category<|im_end|>
<|im_start|>user
{input}<|im_end|>
<|im_start|>assistant
""";

  // 🟢 INCOME PROMPT (Extract Amount ONLY, Default Source to 'ไม่ระบุ')
  static const String kIncomeSystemPrompt = """<|im_start|>system
หน้าที่ของคุณคือแยกข้อมูลรายรับเป็น JSON: amount โดยให้ source เป็น 'ไม่ระบุ'<|im_end|>
<|im_start|>user
{input}<|im_end|>
<|im_start|>assistant
""";

  // 🔵 CATEGORIZATION PROMPT (Simple category only)
  static const String kCategorizeSystemPrompt = """<|im_start|>system
วิเคราะห์ "ชื่อผู้รับโอน" และจัดหมวดหมู่:
- อาหาร (ร้านอาหาร, คาเฟ่, เครื่องดื่ม)
- ช้อปปิ้ง (ร้านค้า, เสื้อผ้า, ของใช้)
- เดินทาง (แท็กซี่, น้ำมัน, ที่พัก)
- บันเทิง (ภาพยนตร์, เกม)
- การลงทุน (หุ้น, กองทุน)
- อื่นๆ (ชื่อคนธรรมดา หรือไม่แน่ใจ)

ตอบกลับเป็น JSON: {"category": "ชื่อหมวดหมู่"}<|im_end|>
<|im_start|>user
{input}<|im_end|>
<|im_start|>assistant
""";

  static const List<String> kBankFolderKeywords = [
    // 🟢 Major Banks (Mobile Banking Apps)
    'k plus', 'kplus',        // Kasikorn (K PLUS)
    'scb', 'easy',            // SCB (SCB EASY)
    'krungthai', 'next',      // Krungthai (Krungthai NEXT)
    'bualuang', 'bangkok',    // Bangkok Bank (Bualuang mBanking)
    'mymo', 'gsb',            // GSB (MyMo)
    'kma', 'krungsri',        // Krungsri (KMA)
    'ttb', 'touch',           // TTB (ttb touch)
    'baac', 'a-mobile',       // BAAC (ธกส.)
    'uob', 'tmrw',            // UOB / TMRW
    'cimb',                   // CIMB Thai
    'lh bank', 'lhb',         // LH Bank
    'kkp',                    // Kiatnakin Phatra
    'ghb', 'gh bank',         // GH Bank (ธอส.)
    'tisco',                  // Tisco

    // 🟠 Digital Banks & Wallets
    'truemoney',              // TrueMoney Wallet (Important!)
    'paotang', 'เป๋าตัง',      // Paotang (G-Wallet)
    'make',                   // MAKE by KBank
    'kept',                   // Kept by Krungsri
    'dime',                   // Dime!
    'shopeepay',              // ShopeePay
    'line pay', 'rabbit',     // Rabbit LINE Pay
    
    // 🟡 Common Folders (User Request)
    'pictures',               // Target: /Internal storage/Pictures/ (Where MyMo slip is)
    'dcim',                   // Optional: Standard photo directory
    'images',                 // Generic fallback
  ];
}