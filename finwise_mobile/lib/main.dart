import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/ai_forecast_screen.dart';
import 'screens/admin_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('vi_VN', null);
  
  // Kiểm tra phiên đăng nhập đã lưu
  await ApiService().checkSavedSession();

  runApp(const FinWiseApp());
}

class FinWiseApp extends StatelessWidget {
  const FinWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinWise AI - Quản Lý Tài Chính',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          primary: const Color(0xFF4F46E5),
          surface: const Color(0xFFF8FAFC),
        ),
        fontFamily: GoogleFonts.outfit().fontFamily,
      ),
      home: ApiService().isLoggedIn
          ? const MainNavigationScreen()
          : const LoginScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(onNavigateTab: (index) => setState(() => _currentIndex = index)),
      const TransactionsScreen(),
      const AiForecastScreen(),
      _buildProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: Colors.white,
        elevation: 10,
        indicatorColor: const Color(0xFF4F46E5).withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Color(0xFF4F46E5)),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF4F46E5)),
            label: 'Giao dịch',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights, color: Color(0xFF4F46E5)),
            label: 'Dự báo AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Color(0xFF4F46E5)),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }

  void _showServerConfigDialog() {
    final ipController = TextEditingController(text: ApiService().baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cấu hình Máy chủ Kết nối', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nếu mở app trên điện thoại thật qua WiFi, hãy nhập địa chỉ IP máy tính (ví dụ: http://192.168.111.92:5000):',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              decoration: InputDecoration(
                labelText: 'Địa chỉ Backend URL',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              ApiService().setCustomBaseUrl(ipController.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã cập nhật máy chủ: ${ApiService().baseUrl}')),
              );
              setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            child: const Text('Lưu cấu hình', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Về FinWise AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ứng Dụng Quản Lý Tài Chính Cá Nhân FinWise', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 6),
            Text('Phiên bản: 1.0.0 (Release 2026)', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            SizedBox(height: 12),
            Text('Hệ sinh thái công nghệ:'),
            Text('• Trợ lý AI nhận diện: PhoBERT NLP', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
            Text('• Dự báo dòng tiền: Time-series LSTM', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
            Text('• Cơ sở dữ liệu: Supabase PostgreSQL Cloud', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
            Text('• Bảo mật: Mã hóa Bcrypt & JWT Token', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            child: const Text('Đóng', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng Xuất', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản hiện tại?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService().logout();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Đăng Xuất', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileScreen() {
    final user = ApiService().currentUser;
    final displayName = user?.fullName.isNotEmpty == true ? user!.fullName : 'Người Dùng FinWise';
    final displayEmail = user?.email.isNotEmpty == true ? user!.email : 'demo@finwise.vn';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Tài Khoản & Cài Đặt',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Thẻ Thông tin cá nhân
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                    child: const Icon(Icons.person, size: 36, color: Color(0xFF4F46E5)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayEmail,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (user?.isAdmin == true ? const Color(0xFF4F46E5) : const Color(0xFF10B981)).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                user?.isAdmin == true ? 'Quản Trị Viên (Admin)' : 'Dữ liệu Riêng tư & Bảo mật',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: user?.isAdmin == true ? const Color(0xFF4F46E5) : const Color(0xFF10B981),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Banner Truy cập Admin Portal (chỉ hiện cho Quản trị viên)
            if (user?.isAdmin == true) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF4338CA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4338CA).withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trung Tâm Quản Trị Hệ Thống',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Giám sát AI Microservices & Phân quyền User',
                                  style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // Nhóm tính năng Quản lý
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEEF2FF),
                      child: Icon(Icons.account_balance_wallet, color: Color(0xFF4F46E5), size: 20),
                    ),
                    title: const Text('Ví Tiền & Nguồn Tiền', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Quản lý các ví và số dư khả dụng', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ví tiền được phân bổ độc lập cho tài khoản của bạn.')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFECFDF5),
                      child: Icon(Icons.category, color: Color(0xFF10B981), size: 20),
                    ),
                    title: const Text('Danh Mục Chi Tiêu Chuẩn', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('10 danh mục hỗ trợ nhận diện tự động AI', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Hệ thống có 10 danh mục chuẩn tích hợp PhoBERT AI.')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFFFBEB),
                      child: Icon(Icons.settings_ethernet, color: Color(0xFFF59E0B), size: 20),
                    ),
                    title: const Text('Cài Đặt Kết Nối Máy Chủ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Cấu hình IP Backend khi dùng trên điện thoại', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    trailing: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF94A3B8)),
                    onTap: _showServerConfigDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF3F4F6),
                      child: Icon(Icons.info_outline, color: Color(0xFF4B5563), size: 20),
                    ),
                    title: const Text('Về Ứng Dụng FinWise AI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Thông tin phiên bản & Công nghệ đồ án', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
                    onTap: _showAboutDialog,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Nút Đăng xuất
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout, color: Color(0xFFEF4444), size: 20),
                label: const Text(
                  'Đăng Xuất Tài Khoản',
                  style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  backgroundColor: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
