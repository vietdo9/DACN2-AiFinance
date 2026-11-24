import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  late TabController _tabController;

  bool _isLoading = true;
  bool _usersLoadFailed = false;
  bool _overviewLoadFailed = false;
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  int _currentPage = 1;
  int _totalUsers = 0;
  int _perPage = 100;
  int _loadRequestId = 0;
  Timer? _searchDebounce;
  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAdminData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminData() async {
    final requestId = ++_loadRequestId;
    setState(() => _isLoading = _overview == null && _users.isEmpty);
    final api = ApiService();
    final overviewData = await api.getAdminOverview();
    final usersResult = await api.getAdminUsers(
      query: _searchQuery,
      page: _currentPage,
      role: _roleFilter,
      status: _statusFilter,
    );

    if (mounted && requestId == _loadRequestId) {
      setState(() {
        _overview = overviewData;
        _overviewLoadFailed = overviewData == null;
        _users = usersResult.users;
        _totalUsers = usersResult.total;
        _perPage = usersResult.perPage;
        _usersLoadFailed = usersResult.failed;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredUsers => _users.where((user) {
    final role = user['role']?.toString() ?? 'user';
    final status = user['status']?.toString() ?? 'active';
    return (_roleFilter == 'all' || role == _roleFilter) &&
        (_statusFilter == 'all' || status == _statusFilter);
  }).toList();

  Widget _filterDropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
    {required double width}
  ) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        selectedItemBuilder: (context) => options.entries
            .map((e) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        items: options.entries
            .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _buildUsersTable(List<Map<String, dynamic>> users) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('Tài khoản')),
                DataColumn(label: Text('Vai trò')),
                DataColumn(label: Text('Trạng thái')),
                DataColumn(label: Text('Giao dịch')),
                DataColumn(label: Text('Ví')),
                DataColumn(label: Text('Thao tác')),
              ],
              rows: users.map((user) {
                final role = user['role']?.toString() ?? 'user';
                final status = user['status']?.toString() ?? 'active';
                final isAdmin = role == 'admin';
                final hasRootMarker =
                    user.containsKey('is_root_admin') ||
                    user.containsKey('isRootAdmin');
                final root =
                    user['is_root_admin'] == true ||
                    user['isRootAdmin'] == true ||
                    (isAdmin && !hasRootMarker);
                final canSuspend =
                    user['can_suspend'] == true || user['canSuspend'] == true;
                final canRole =
                    user['can_change_role'] == true ||
                    user['canChangeRole'] == true;
                final canDelete =
                    user['can_delete'] == true || user['canDelete'] == true;
                final actions = <Widget>[
                  if (canSuspend)
                    IconButton(
                      tooltip: status == 'active'
                          ? 'Khóa tài khoản'
                          : 'Mở khóa tài khoản',
                      icon: Icon(
                        status == 'active'
                            ? Icons.lock_outline
                            : Icons.lock_open,
                        size: 18,
                      ),
                      onPressed: () => _toggleUserStatus(user),
                    ),
                  if (canRole)
                    IconButton(
                      tooltip: isAdmin ? 'Hạ quyền' : 'Cấp quyền admin',
                      icon: const Icon(
                        Icons.manage_accounts_outlined,
                        size: 18,
                      ),
                      onPressed: () => _toggleUserRole(user),
                    ),
                  if (canDelete)
                    IconButton(
                      tooltip: 'Xóa tài khoản',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      onPressed: () => _deleteUser(user),
                    ),
                  if (root)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Root Admin',
                        style: TextStyle(
                          color: Color(0xFF4F46E5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ];
                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 280,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              user['full_name']?.toString() ?? 'Người Dùng',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              user['email']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text(role.toUpperCase())),
                    DataCell(
                      Text(status == 'active' ? 'Hoạt động' : 'Tạm khóa'),
                    ),
                    DataCell(Text('${user['transaction_count'] ?? 0}')),
                    DataCell(Text('${user['wallet_count'] ?? 0}')),
                    DataCell(
                      Row(mainAxisSize: MainAxisSize.min, children: actions),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final currentStatus = user['status']?.toString() ?? 'active';
    final newStatus = currentStatus == 'active' ? 'suspended' : 'active';
    final actionText = newStatus == 'suspended' ? 'Khóa' : 'Mở khóa';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '$actionText tài khoản?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Bạn có chắc chắn muốn $actionText tài khoản [${user['email']}] không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'suspended'
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
            ),
            child: Text(
              actionText,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ApiService().updateUserStatus(user['id'], newStatus);
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã $actionText tài khoản ${user['email']} thành công!',
              ),
              backgroundColor: newStatus == 'suspended'
                  ? Colors.orange
                  : Colors.green,
            ),
          );
          _loadAdminData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Thao tác không thành công.'),
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleUserRole(Map<String, dynamic> user) async {
    final currentRole = user['role']?.toString() ?? 'user';
    final newRole = currentRole == 'admin' ? 'user' : 'admin';
    final roleName = newRole == 'admin'
        ? 'Quản Trị Viên (Admin)'
        : 'Người Dùng (User)';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Phân quyền tài khoản',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Chuyển vai trò của [${user['email']}] thành [$roleName]?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
            ),
            child: const Text(
              'Xác nhận',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ApiService().updateUserRole(user['id'], newRole);
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã cập nhật quyền thành $roleName!')),
          );
          _loadAdminData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Không thể cập nhật vai trò.'),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final email = user['email']?.toString() ?? '';
    var typedEmail = '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Xóa tài khoản vĩnh viễn?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFEF4444),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Xóa tài khoản $email và dữ liệu liên quan? Không thể hoàn tác.',
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (value) {
                  typedEmail = value;
                  setDialogState(() {});
                },
                decoration: const InputDecoration(
                  labelText: 'Nhập lại email để xác nhận',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed:
                  typedEmail.trim() == email
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
              child: const Text(
                'Xóa Vĩnh Viễn',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final result = await ApiService().deleteUser(
        user['id'],
        confirmEmail: typedEmail.trim(),
      );
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa người dùng ${user['email']} thành công!'),
            ),
          );
          _loadAdminData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? 'Không thể xóa tài khoản.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1B4B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings, color: Color(0xFF818CF8), size: 22),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FinWise Admin Console',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                Text(
                  'Trung tâm Kiểm soát & Quản trị Hệ thống',
                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Làm mới số liệu',
            onPressed: _loadAdminData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: const Color(0xFF818CF8),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.speed, size: 20), text: 'Tổng Quan & AI'),
            Tab(icon: Icon(Icons.people_alt_outlined, size: 20), text: 'Người Dùng'),
            Tab(icon: Icon(Icons.settings_suggest_outlined, size: 20), text: 'Hạ Tầng'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4F46E5)),
                  SizedBox(height: 16),
                  Text('Đang nạp dữ liệu Quản trị viên...', style: TextStyle(color: Color(0xFF64748B))),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildUsersTab(),
                _buildSystemTab(),
              ],
            ),
    );
  }

  // ==========================================
  // TAB 1: TỔNG QUAN & GIÁM SÁT AI
  // ==========================================
  Widget _buildOverviewTab() {
    if (_overviewLoadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 10),
            const Text('Không thể tải số liệu tổng quan'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loadAdminData,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    final metrics = _overview?['metrics'] ?? {};
    final ai = _overview?['ai_service'] ?? {};
    final categories = (_overview?['category_distribution'] as List?) ?? [];

    final totalUsers = metrics['total_users'] ?? 0;
    final activeUsers = metrics['active_users'] ?? 0;
    final totalTxs = metrics['total_transactions'] ?? 0;
    final totalVolume = (metrics['total_volume'] as num?)?.toDouble() ?? 0.0;

    final aiStatusKnown = ai['status'] == 'online' || ai['status'] == 'offline';
    final isAiOnline = ai['status'] == 'online';

    return RefreshIndicator(
      onRefresh: _loadAdminData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KPI Grid Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Tổng Người Dùng',
                        value: '$totalUsers',
                        subtext: '$activeUsers đang hoạt động',
                        icon: Icons.people,
                        color: const Color(0xFF4F46E5),
                        bgTint: const Color(0xFFEEF2FF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Tổng Giao Dịch',
                        value: '$totalTxs',
                        subtext: 'Toàn hệ thống',
                        icon: Icons.receipt_long,
                        color: const Color(0xFF0EA5E9),
                        bgTint: const Color(0xFFE0F2FE),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Tổng Dòng Tiền',
                        value: currencyFormat.format(totalVolume),
                        subtext: 'Luân chuyển qua ví',
                        icon: Icons.account_balance_wallet,
                        color: const Color(0xFF10B981),
                        bgTint: const Color(0xFFECFDF5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Trạng Thái AI',
                        value: isAiOnline
                            ? 'Hoạt Động'
                            : aiStatusKnown
                            ? 'Chưa sẵn sàng'
                            : 'Chưa có dữ liệu',
                        subtext: isAiOnline
                            ? '${ai['latency_ms'] ?? '—'}ms - Sẵn sàng'
                            : aiStatusKnown
                            ? 'Dịch vụ đang ngoại tuyến'
                            : 'Trạng thái chưa được báo cáo',
                        icon: Icons.psychology,
                        color: isAiOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        bgTint: isAiOnline
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFFFBEB),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // AI Microservice Monitor Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E1B4B).withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.hub_outlined,
                                color: Color(0xFF818CF8),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Giám Sát AI Microservices',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (isAiOnline
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF59E0B))
                                      .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isAiOnline
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 4,
                                  backgroundColor: isAiOnline
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF59E0B),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isAiOnline
                                      ? 'ONLINE'
                                      : aiStatusKnown
                                      ? 'OFFLINE'
                                      : 'UNKNOWN',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isAiOnline
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFFFCD34D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildAiModuleRow(
                        name: 'PhoBERT NLP Classifier',
                        desc: 'Nhận diện & tự động gán nhãn 10 danh mục chi tiêu tiếng Việt',
                        isLoaded: ai['phobert_loaded'] == true
                            ? true
                            : ai['phobert_loaded'] == false
                            ? false
                            : null,
                      ),
                      const Divider(color: Color(0xFF4338CA), height: 16),
                      _buildAiModuleRow(
                        name: 'Time-Series LSTM Forecaster',
                        desc: 'Dự báo xu hướng tài chính & dòng tiền 7 ngày tiếp theo',
                        isLoaded: ai['lstm_loaded'] == true
                            ? true
                            : ai['lstm_loaded'] == false
                            ? false
                            : null,
                      ),
                      const Divider(color: Color(0xFF4338CA), height: 16),
                      _buildAiModuleRow(
                        name: 'EasyOCR Receipt Scanner',
                        desc:
                            'Trích xuất song ngữ Việt - Anh hóa đơn thanh toán',
                        isLoaded: ai['ocr_loaded'] == true
                            ? true
                            : ai['ocr_loaded'] == false
                            ? false
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Thiết bị thực thi: ${ai['device'] ?? 'Chưa có dữ liệu'} (${ai['gpu_name'] ?? 'GPU chưa báo cáo'})',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFC7D2FE),
                              ),
                            ),
                            Text(
                              'Độ trễ: ${ai['latency_ms'] ?? '—'}ms',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF34D399),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Phân bổ chi tiêu toàn hệ thống
                const Text(
                  'Phân Bổ Chi Tiêu Toàn Hệ Thống',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Dữ liệu tổng hợp từ các giao dịch của người dùng',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),

                if (categories.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'Chưa có giao dịch chi tiêu nào để phân tích',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: categories.map((cat) {
                        final colorHex =
                            (cat['color'] as String?)?.replaceFirst('#', '') ??
                            '6366F1';
                        final color = Color(
                          int.parse('FF$colorHex', radix: 16),
                        );
                        final percent =
                            (cat['percent'] as num?)?.toDouble() ?? 0.0;
                        final amount =
                            (cat['amount'] as num?)?.toDouble() ?? 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 5,
                                        backgroundColor: color,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        cat['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '(${cat['count']} GD)',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    currencyFormat.format(amount),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: percent / 100,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  color,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                minHeight: 6,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
    required Color bgTint,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: bgTint, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(subtext, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _buildAiModuleRow({
    required String name,
    required String desc,
    required bool? isLoaded,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isLoaded == true
              ? Icons.check_circle
              : isLoaded == false
              ? Icons.error_outline
              : Icons.help_outline,
          color: isLoaded == true
              ? const Color(0xFF34D399)
              : isLoaded == false
              ? const Color(0xFFF87171)
              : const Color(0xFFFBBF24),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$desc · ${isLoaded == true
                    ? 'Đã tải'
                    : isLoaded == false
                    ? 'Chưa tải'
                    : 'Chưa có dữ liệu'}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: QUẢN LÝ NGƯỜI DÙNG (USERS)
  // ==========================================
  Widget _buildUsersTab() {
    return Column(
      children: [
        // Thanh Tìm kiếm
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
                _currentPage = 1;
              });
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 350),
                _loadAdminData,
              );
            },
            decoration: InputDecoration(
              hintText: 'Tìm kiếm theo email, họ tên...',
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF64748B),
                size: 20,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        _currentPage = 1;
                        _loadAdminData();
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: LayoutBuilder(builder: (context, constraints) {
            final fieldWidth = constraints.maxWidth < 190
                ? constraints.maxWidth
                : 190.0;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
              _filterDropdown(
                'Vai trò',
                _roleFilter,
                const {
                  'all': 'Tất cả vai trò',
                  'admin': 'Admin',
                  'user': 'User',
                },
                (v) {
                  setState(() {
                    _roleFilter = v;
                    _currentPage = 1;
                  });
                  _loadAdminData();
                },
                width: fieldWidth,
              ),
              _filterDropdown(
                'Trạng thái',
                _statusFilter,
                const {
                  'all': 'Tất cả trạng thái',
                  'active': 'Hoạt động',
                  'suspended': 'Tạm khóa',
                },
                (v) {
                  setState(() {
                    _statusFilter = v;
                    _currentPage = 1;
                  });
                  _loadAdminData();
                },
                width: fieldWidth,
              ),
              ],
            );
          }),
        ),

        // Danh sách Người Dùng
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAdminData,
            child: _usersLoadFailed
                ? ListView(
                    children: [
                      SizedBox(
                        height: 220,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                size: 40,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(height: 10),
                              const Text('Không thể tải danh sách tài khoản'),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _loadAdminData,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Thử lại'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : _filteredUsers.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                        height: 220,
                        child: Center(
                          child: Text(
                            _users.isEmpty
                                ? 'Chưa có tài khoản người dùng'
                                : 'Không có tài khoản khớp bộ lọc',
                            style: const TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 1100
                        ? _buildUsersTable(_filteredUsers)
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredUsers.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, index) {
                              final user = _filteredUsers[index];
                              final email = user['email']?.toString() ?? '';
                              final fullName =
                                  user['full_name']?.toString() ?? 'Người Dùng';
                              final role = user['role']?.toString() ?? 'user';
                              final status =
                                  user['status']?.toString() ?? 'active';
                              final txCount = user['transaction_count'] ?? 0;

                              final isAdmin = role == 'admin';
                              final isSuspended = status == 'suspended';
                              final hasRootMarker =
                                  user.containsKey('is_root_admin') ||
                                  user.containsKey('isRootAdmin');
                              final isRootAdmin =
                                  user['is_root_admin'] == true ||
                                  user['isRootAdmin'] == true ||
                                  (isAdmin && !hasRootMarker);
                              final canSuspend =
                                  user['can_suspend'] == true ||
                                  user['canSuspend'] == true;
                              final canChangeRole =
                                  user['can_change_role'] == true ||
                                  user['canChangeRole'] == true;
                              final canDelete =
                                  user['can_delete'] == true ||
                                  user['canDelete'] == true;

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSuspended
                                        ? const Color(0xFFFCA5A5)
                                        : Colors.transparent,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: isAdmin
                                              ? const Color(0xFF4F46E5)
                                                    .withValues(alpha: 0.12)
                                              : const Color(0xFF0EA5E9)
                                                    .withValues(alpha: 0.12),
                                          child: Icon(
                                            isAdmin
                                                ? Icons.shield
                                                : Icons.person,
                                            color: isAdmin
                                                ? const Color(0xFF4F46E5)
                                                : const Color(0xFF0EA5E9),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      fullName,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                        color: Color(
                                                          0xFF1E293B,
                                                        ),
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  // Role Badge
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isAdmin
                                                          ? const Color(
                                                              0xFFEEF2FF,
                                                            )
                                                          : const Color(
                                                              0xFFF1F5F9,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: isAdmin
                                                            ? const Color(
                                                                0xFFC7D2FE,
                                                              )
                                                            : const Color(
                                                                0xFFE2E8F0,
                                                              ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      isAdmin
                                                          ? 'ADMIN'
                                                          : 'USER',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isAdmin
                                                            ? const Color(
                                                                0xFF4F46E5,
                                                              )
                                                            : const Color(
                                                                0xFF64748B,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  // Status Badge
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isSuspended
                                                          ? const Color(
                                                              0xFFFEF2F2,
                                                            )
                                                          : const Color(
                                                              0xFFECFDF5,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      isSuspended
                                                          ? 'TẠM KHÓA'
                                                          : 'HOẠT ĐỘNG',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isSuspended
                                                            ? const Color(
                                                                0xFFEF4444,
                                                              )
                                                            : const Color(
                                                                0xFF10B981,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                email,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),
                                    const Divider(
                                      height: 1,
                                      color: Color(0xFFF1F5F9),
                                    ),
                                    const SizedBox(height: 10),

                                    // Thông số giao dịch cá nhân
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.receipt_outlined,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$txCount giao dịch',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Icon(
                                              Icons
                                                  .account_balance_wallet_outlined,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${user['wallet_count'] ?? 0} ví',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),

                                        // Thao tác (chỉ hiện nếu không phải Root Admin)
                                        if (canSuspend ||
                                            canChangeRole ||
                                            canDelete)
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                              Icons.more_vert,
                                              size: 20,
                                              color: Color(0xFF64748B),
                                            ),
                                            onSelected: (val) {
                                              if (val == 'status')
                                                _toggleUserStatus(user);
                                              if (val == 'role')
                                                _toggleUserRole(user);
                                              if (val == 'delete')
                                                _deleteUser(user);
                                            },
                                            itemBuilder: (ctx) => [
                                              if (canSuspend)
                                                PopupMenuItem(
                                                  value: 'status',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        isSuspended
                                                            ? Icons.lock_open
                                                            : Icons.block,
                                                        size: 18,
                                                        color: isSuspended
                                                            ? Colors.green
                                                            : Colors.orange,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        isSuspended
                                                            ? 'Mở khóa tài khoản'
                                                            : 'Khóa tài khoản',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (canChangeRole)
                                                PopupMenuItem(
                                                  value: 'role',
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.manage_accounts,
                                                        size: 18,
                                                        color: Color(
                                                          0xFF4F46E5,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        isAdmin
                                                            ? 'Hạ cấp xuống User'
                                                            : 'Thăng cấp Quản Trị',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (canDelete)
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.delete_outline,
                                                        size: 18,
                                                        color: Colors.red,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Xóa tài khoản',
                                                        style: TextStyle(
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          )
                                        else if (isRootAdmin)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Root Admin',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF4F46E5),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$_totalUsers tài khoản · Trang $_currentPage/${((_totalUsers - 1) ~/ _perPage + 1).clamp(1, 99999)}',
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Trang trước',
                onPressed: _currentPage > 1
                    ? () {
                        setState(() => _currentPage--);
                        _loadAdminData();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Trang sau',
                onPressed: _currentPage * _perPage < _totalUsers
                    ? () {
                        setState(() => _currentPage++);
                        _loadAdminData();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 3: HẠ TẦNG & CẤU HÌNH HỆ THỐNG
  // ==========================================
  Widget _buildSystemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSection(
            title: 'Hạ Tầng Backend & Cloud',
            items: [
              _buildInfoRow(
                'API Gateway',
                'Node.js Express (Render Cloud 24/7)',
              ),
              _buildInfoRow('Backend URL', ApiService().baseUrl),
              _buildInfoRow(
                'Cơ sở dữ liệu',
                'Supabase PostgreSQL Cloud (Tokyo, AWS)',
              ),
              _buildInfoRow(
                'Xác thực bảo mật',
                'Bcrypt Hashing + JWT Role-Based Access Control',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoSection(
            title: 'Các Mô Hình AI Được Triển Khai',
            items: [
              _buildInfoRow(
                'Phân loại NLP',
                'PhoBERT-base (VinAI Research, CC-BY-SA-4.0)',
              ),
              _buildInfoRow(
                'Số danh mục chuẩn',
                '10 Danh mục tài chính tiêu chuẩn Việt Nam',
              ),
              _buildInfoRow(
                'Dự báo dòng tiền',
                'Mạng Nơ-ron Hồi quy LSTM (Time-series)',
              ),
              _buildInfoRow(
                'Chu kỳ dự báo',
                'Dự đoán chi tiêu 7 ngày tiếp theo',
              ),
              _buildInfoRow(
                'Quét Hóa Đơn OCR',
                'Bilingual EasyOCR vi-en (Clova AI / JaidedAI)',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoSection(
            title: 'Quyền Hạn Tài Khoản Quản Trị',
            items: [
              _buildInfoRow(
                'Quản trị gốc',
                'Được cấu hình riêng ở phía máy chủ',
              ),
              _buildInfoRow(
                'Chính sách riêng tư',
                'Bảo mật: Không can thiệp chi tiết giao dịch nhạy cảm',
              ),
              _buildInfoRow(
                'Phân quyền truy cập',
                'Chỉ người dùng role: admin mới xem được bảng này',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection({required String title, required List<Widget> items}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }
}
