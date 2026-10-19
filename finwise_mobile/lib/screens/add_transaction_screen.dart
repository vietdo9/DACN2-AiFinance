import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../models/category_model.dart';
import '../services/api_service.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  String _type = 'expense'; // 'expense' hoặc 'income'
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  List<CategoryModel> _categories = [];
  String? _selectedCategoryCode;
  bool _isLoadingCategories = true;
  bool _isClassifying = false;
  bool _isScanningBill = false;
  String? _aiFeedbackMessage;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final list = await ApiService().getCategories();
    if (mounted) {
      setState(() {
        _categories = list;
        _isLoadingCategories = false;
        if (_categories.isNotEmpty) {
          _selectedCategoryCode = _categories.first.code;
        }
      });
    }
  }

  // Gọi PhoBERT AI để tự phân loại từ câu ghi chú
  Future<void> _triggerAiClassify() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập ghi chú giao dịch trước khi gọi AI!')),
      );
      return;
    }

    setState(() => _isClassifying = true);
    final result = await ApiService().classifyWithAi(note);

    if (mounted) {
      setState(() => _isClassifying = false);

      if (result != null && result['category_code'] != null) {
        final code = result['category_code'];
        final name = result['category_name'];
        final conf = ((result['confidence'] as num?)?.toDouble() ?? 0.0) * 100;

        setState(() {
          _selectedCategoryCode = code;
          _aiFeedbackMessage = '✨ AI nhận diện: $name (${conf.toStringAsFixed(1)}% tin cậy)';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF4F46E5),
            content: Text('✨ AI đã tự động chọn danh mục: $name'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể kết nối AI, vui lòng chọn danh mục thủ công.')),
        );
      }
    }
  }

  // Mở menu chọn Camera hoặc Thư viện ảnh
  void _showScanBillOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Quét Hóa Đơn Tự Động (AI OCR)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sử dụng mô hình EasyOCR & PhoBERT để nhận diện và bóc tách thông tin',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF4F46E5), size: 24),
                ),
                title: const Text('Chụp ảnh từ Máy ảnh', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: const Text('Mở camera chụp trực tiếp bill/hóa đơn thanh toán'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndScanBill(ImageSource.camera);
                },
              ),
              const Divider(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF10B981), size: 24),
                ),
                title: const Text('Chọn ảnh từ Thư viện', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: const Text('Tải ảnh hóa đơn / biên lai chụp sẵn trong máy'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndScanBill(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // Thực hiện chọn ảnh và gửi sang Backend / AI Service
  Future<void> _pickAndScanBill(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _isScanningBill = true;
        _aiFeedbackMessage = '⏳ Đang phân tích hóa đơn bằng EasyOCR & PhoBERT...';
      });

      final bytes = await pickedFile.readAsBytes();
      final result = await ApiService().scanBill(
        imageBytes: bytes,
        filename: pickedFile.name.isNotEmpty ? pickedFile.name : 'bill.jpg',
      );

      if (!mounted) return;

      setState(() => _isScanningBill = false);

      if (result != null) {
        final totalAmount = result['total_amount'] as num? ?? 0;
        final merchant = result['merchant'] as String? ?? 'Hóa đơn thanh toán';
        final categoryCode = result['category_code'] as String?;
        final categoryName = result['category_name'] as String? ?? 'Danh mục';
        final dateStr = result['date'] as String?;
        final confidence = ((result['confidence'] as num?)?.toDouble() ?? 0.0) * 100;

        setState(() {
          _type = 'expense';
          if (totalAmount > 0) {
            _amountController.text = totalAmount.toInt().toString();
          }
          _noteController.text = merchant;
          if (categoryCode != null && _categories.any((c) => c.code == categoryCode)) {
            _selectedCategoryCode = categoryCode;
          }
          if (dateStr != null) {
            try {
              _selectedDate = DateTime.parse(dateStr);
            } catch (_) {}
          }
          _aiFeedbackMessage = '✨ Đã quét: $merchant - ${NumberFormat('#,###', 'vi_VN').format(totalAmount)}đ ($categoryName, ${confidence.toStringAsFixed(1)}% tin cậy)';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đã quét xong: $merchant (${NumberFormat('#,###', 'vi_VN').format(totalAmount)}đ)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        setState(() {
          _aiFeedbackMessage = '❌ Không thể quét hóa đơn. Vui lòng thử lại với ảnh rõ hơn hoặc nhập tay.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Không thể quét hóa đơn. Vui lòng kiểm tra lại ảnh hoặc kết nối server!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanningBill = false;
          _aiFeedbackMessage = '❌ Lỗi quét hóa đơn: $e';
        });
      }
    }
  }

  Future<void> _saveTransaction() async {
    final amountText = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập số tiền hợp lệ!')),
      );
      return;
    }

    final success = await ApiService().createTransaction(
      amount: amount,
      note: _noteController.text.trim(),
      type: _type,
      categoryCode: _selectedCategoryCode,
    );

    if (mounted) {
      if (success) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi khi lưu giao dịch.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Thêm Giao Dịch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Nút / Banner Quét Hóa Đơn AI
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _isScanningBill ? null : _showScanBillOptions,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _isScanningBill
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isScanningBill ? 'Đang quét & phân tích bill...' : 'Quét Hóa Đơn Tự Động (AI OCR)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _isScanningBill
                                    ? 'EasyOCR & PhoBERT đang trích xuất dữ liệu...'
                                    : 'Chụp hoặc tải ảnh bill để tự điền tiền & danh mục',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_isScanningBill)
                          const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 1. Chuyển đổi Loại: Chi Tiêu / Thu Nhập
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _type = 'expense'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'expense' ? const Color(0xFFEF4444) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Khoản Chi',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _type == 'expense' ? Colors.white : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _type = 'income'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'income' ? const Color(0xFF10B981) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Thu Nhập',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _type == 'income' ? Colors.white : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Ô nhập số tiền
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Số tiền (VNĐ)', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _type == 'expense' ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    ),
                    decoration: const InputDecoration(
                      hintText: '0 đ',
                      border: InputBorder.none,
                      prefixText: '₫ ',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3. Ô nhập Ghi chú có nút Trí Tuệ Nhân Tạo (PhoBERT AI)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ghi chú giao dịch', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEEF2FF),
                          foregroundColor: const Color(0xFF4F46E5),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFFC7D2FE)),
                          ),
                        ),
                        onPressed: _isClassifying ? null : _triggerAiClassify,
                        icon: _isClassifying
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome, size: 14),
                        label: const Text('AI Tự Phân Loại', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      hintText: 'Ví dụ: Ăn lẩu haidilao 500k, đổ xăng wave 60k...',
                      border: InputBorder.none,
                    ),
                  ),
                  if (_aiFeedbackMessage != null) ...[
                    const Divider(height: 16),
                    Text(
                      _aiFeedbackMessage!,
                      style: const TextStyle(color: Color(0xFF4F46E5), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 4. Chọn Ngày Giao Dịch
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Color(0xFF64748B), size: 18),
                    const SizedBox(width: 10),
                    Text('Ngày: ${dateFormat.format(_selectedDate)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 5. Chọn Danh mục (Grid các danh mục chuẩn)
            const Text('Chọn Danh Mục', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 10),

            if (_isLoadingCategories)
              const Center(child: CircularProgressIndicator())
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.95,
                ),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat.code == _selectedCategoryCode;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategoryCode = cat.code),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? cat.color.withOpacity(0.12) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? cat.color : const Color(0xFFE2E8F0),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(cat.iconData, color: cat.color, size: 24),
                          const SizedBox(height: 6),
                          Text(
                            cat.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? cat.color : const Color(0xFF334155),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 30),

            // 6. Nút Lưu
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveTransaction,
                child: const Text('Lưu Giao Dịch', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
