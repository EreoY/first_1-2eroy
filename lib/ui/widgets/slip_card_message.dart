import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chat_message.dart';
import '../../utils/category_styles.dart';
import '../../services/category_classifier_service.dart';

class SlipCardMessageWidget extends StatefulWidget {
  final ChatMessage message;
  final Function(ChatMessage, Map<String, dynamic>) onSave;
  final Function(ChatMessage)? onDelete;
  final Function(String)? onCategoryChanged;

  const SlipCardMessageWidget({
    super.key,
    required this.message,
    required this.onSave,
    this.onDelete,
    this.onCategoryChanged,
  });

// ... (inside State class)



  @override
  State<SlipCardMessageWidget> createState() => _SlipCardMessageWidgetState();
}

class _SlipCardMessageWidgetState extends State<SlipCardMessageWidget> {
  late TextEditingController _bankController;
  late TextEditingController _amountController;
  late TextEditingController _memoController;
  late DateTime _date;
  String _selectedCategory = 'Uncategorized';

  final List<String> _categories = [
    'Uncategorized',
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Transfer',
    'Entertainment',
    'Health',
  ];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    final data = widget.message.slipData ?? {};
    
    // Bank + Time
    String bankName = data['bank'] ?? 'Unknown Bank';
    DateTime date;
    if (data['date'] is DateTime) {
      date = data['date'];
    } else if (data['date'] is String) {
       try {
         date = DateTime.parse(data['date']);
       } catch (_) {
         date = DateTime.now();
       }
    } else {
      date = DateTime.now();
    }
    _date = date;

    _bankController = TextEditingController(text: '$bankName at ${DateFormat('HH:mm').format(_date)}');
    _amountController = TextEditingController(text: (data['amount'] ?? 0.0).toString());
    // Pre-fill Memo with Recipient if available (since OCR Memo is disabled)
    String initialMemo = data['memo'] ?? data['recipient'] ?? '';
    _memoController = TextEditingController(text: initialMemo);

    // FIX: Sync initial memo back to data model if it was null
    if (data['memo'] == null && initialMemo.isNotEmpty) {
       if (widget.message.slipData == null) {
          widget.message.slipData = {};
       }
       widget.message.slipData!['memo'] = initialMemo;
    }

    // Smart Category - ใช้จาก LLM ถ้ามี ไม่งั้นใช้ rule-based
    if (data['category'] != null && data['category'] != 'Uncategorized' && data['category'] != 'อื่นๆ') {
      // ✅ มี category จาก LLM แล้ว - แปลงจากภาษาไทยเป็นอังกฤษ
      String llmCategory = data['category'];
      _selectedCategory = CategoryStyles.thaiToEnglish(llmCategory);
      
      // Sync กลับไปที่ data model เป็นภาษาอังกฤษ
      if (widget.message.slipData == null) {
        widget.message.slipData = {};
      }
      widget.message.slipData!['category'] = _selectedCategory;
      print("[SlipCard] ✅ ใช้ category จาก LLM: $llmCategory → $_selectedCategory");
    } else {
      // ❌ ยังไม่มี category หรือเป็น fallback - ใช้ rule-based
      String recipient = data['recipient'] ?? '';
      String contextText = "$bankName $recipient $initialMemo";
      String suggested = CategoryClassifierService().suggestCategory(contextText);
      if (suggested != 'Uncategorized') {
        _selectedCategory = suggested;
        
        if (widget.message.slipData == null) {
          widget.message.slipData = {};
        }
        widget.message.slipData!['category'] = suggested;
        print("[SlipCard] ⚠️ Fallback: ใช้ rule-based category: $suggested");
      } else {
        _selectedCategory = 'Uncategorized';
      }
    }
  }

  @override
  void dispose() {
    _bankController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _date) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute);
      });
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยกเลิกรายการ?"),
        content: const Text("คุณต้องการลบรายการนี้ใช่หรือไม่?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ไม่"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ใช่, ลบเลย"),
          ),
        ],
      ),
    );

    if (confirm == true && widget.onDelete != null) {
      widget.onDelete!(widget.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = widget.message.isSaved;
    final imagePath = widget.message.imagePath;
    final hasData = widget.message.slipData != null;

    // Use standard chat bubble constraints
    final maxWidth = MediaQuery.of(context).size.width * 0.8;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: isSaved ? null : Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Image Header (Tappable)
                  if (imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Scaffold(
                                appBar: AppBar(backgroundColor: Colors.black),
                                backgroundColor: Colors.black,
                                body: Center(child: Image.file(File(imagePath))),
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            color: Colors.grey[100], // Distinct background for image area
                            width: double.infinity,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 250), // Limit height
                              child: Image.file(
                                File(imagePath),
                                fit: BoxFit.contain, // Show full image
                                cacheWidth: 500, // Optimize memory usage
                                errorBuilder: (c, e, s) => const SizedBox(
                                  height: 100,
                                  child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 2. Header (Like AIExpenseCard)
                  Row(
                    children: [
                      Icon(Icons.receipt_long, size: 16, color: Colors.amber[700]),
                      const SizedBox(width: 8),
                      Text(
                        "สลิปโอนเงิน",
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.bold, 
                          color: Colors.amber[800]
                        ),
                      ),
                    ],
                  ),
                  
                  // Date Picker (Like AIExpenseCard)
                  InkWell(
                    onTap: isSaved ? null : _pickDate,
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          "วันที่: ${DateFormat('dd/MM/yyyy HH:mm').format(_date)}",
                          style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                        ),
                        if (!isSaved)
                          Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[600]),
                      ],
                    ),
                  ),
                  const Divider(),

                  if (!hasData)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text("กำลังอ่านข้อมูล...", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  else if (widget.message.slipData!['error'] == true)
                     Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(child: Text("อ่านสลิปไม่ได้ กรุณากรอกเอง", style: TextStyle(color: Colors.red[300], fontSize: 12))),
                        ],
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Item Row (Like AIExpenseCard)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: CategoryStyles.getColor(_selectedCategory).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  CategoryStyles.getIcon(_selectedCategory),
                                  size: 16,
                                  color: CategoryStyles.getColor(_selectedCategory),
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // Inputs
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Item Name (Memo)
                                    TextFormField(
                                      controller: _memoController,
                                      enabled: !isSaved,
                                      onChanged: (val) {
                                        // Direct Update: Sync memo immediately
                                        if (widget.message.slipData != null) {
                                          widget.message.slipData!['memo'] = val;
                                        }
                                      },
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                                        border: InputBorder.none,
                                        hintText: 'รายการ...',
                                      ),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    
                                    // Category Dropdown (Small)
                                    if (!isSaved)
                                      SizedBox(
                                        height: 24,
                                        child: DropdownButton<String>(
                                          value: _categories.contains(_selectedCategory) ? _selectedCategory : 'Uncategorized',
                                          isDense: true,
                                          underline: Container(),
                                          icon: const Icon(Icons.arrow_drop_down, size: 16),
                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                          items: _categories.map((c) => DropdownMenuItem(
                                            value: c, 
                                            child: Row(
                                              children: [
                                                Icon(CategoryStyles.getIcon(c), size: 14, color: CategoryStyles.getColor(c)),
                                                const SizedBox(width: 8),
                                                Text(CategoryStyles.getThaiName(c)),
                                              ],
                                            ),
                                          )).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              print("DEBUG: SlipCard Dropdown Changed to: $val");
                                              setState(() => _selectedCategory = val);
                                              
                                              // Direct Update: Update the source of truth immediately
                                              if (widget.message.slipData != null) {
                                                widget.message.slipData!['category'] = val;
                                                // Optional: Save to Hive immediately to persist across restarts
                                                // widget.message.save(); 
                                              }

                                              if (widget.onCategoryChanged != null) {
                                                widget.onCategoryChanged!(val);
                                              }
                                            }
                                          },
                                        ),
                                      )
                                    else
                                      Row(
                                        children: [
                                          Icon(CategoryStyles.getIcon(_selectedCategory), size: 12, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Text(CategoryStyles.getThaiName(_selectedCategory), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        ],
                                      ),
                                    
                                    // Bank Info (Subtitle)
                                    Text(
                                      _bankController.text,
                                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(width: 8),

                              // Price
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  controller: _amountController,
                                  enabled: !isSaved,
                                  textAlign: TextAlign.right,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                                    border: InputBorder.none,
                                    prefixText: '฿',
                                  ),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(),

                        // Save Button
                        if (!isSaved)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                  print("DEBUG: SlipCard Saving - Selected Category: $_selectedCategory");
                                  final updatedSlipData = {
                                    'bank': _bankController.text,
                                    'amount': double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0,
                                    'date': _date,
                                    'memo': _memoController.text,
                                    'category': _selectedCategory,
                                  };
                                  // Update local object too
                                  widget.message.slipData = updatedSlipData;
                                  
                                  print("DEBUG: SlipCard Saving - Updated slipData: $updatedSlipData");
                                  widget.onSave(widget.message, updatedSlipData);
                                },
                              icon: const Icon(Icons.check_circle_outline, size: 18),
                              label: const Text("ยืนยันและบันทึก"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text("บันทึกแล้ว ✓", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            
            // Delete Button (Top Right)
            if (!isSaved && widget.onDelete != null)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _confirmDelete,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.red),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
