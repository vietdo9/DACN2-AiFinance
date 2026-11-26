import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/finwise_brand_mark.dart';
import 'login_screen.dart';

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
  bool _overviewLoading = true;
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  int _currentPage = 1;
  int _totalUsers = 0;
  int _perPage = 100;
  int _loadRequestId = 0;
  int _overviewRequestId = 0;
  String _overviewPeriod = 'all';
  DateTime _overviewDate = _vietnamToday();
  Timer? _searchDebounce;
  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  static const _ink = Color(0xFF17212B);
  static const _mutedInk = Color(0xFF65717D);
  static const _paper = Color(0xFFF4F6F7);
  static const _line = Color(0xFFE1E6E9);
  static const _accent = Color(0xFF4F46E5);

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
    await Future.wait([_loadUsers(), _loadOverview()]);
  }

  Future<void> _loadUsers() async {
    final requestId = ++_loadRequestId;
    setState(() => _isLoading = _overview == null && _users.isEmpty);
    final usersResult = await ApiService().getAdminUsers(
      query: _searchQuery,
      page: _currentPage,
      role: _roleFilter,
      status: _statusFilter,
    );
    if (mounted && requestId == _loadRequestId) {
      setState(() {
        _users = usersResult.users;
        _totalUsers = usersResult.total;
        _perPage = usersResult.perPage;
        _usersLoadFailed = usersResult.failed;
        _isLoading = false;
      });
    }
  }

  static DateTime _vietnamToday() {
    final vietnamNow = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime.utc(vietnamNow.year, vietnamNow.month, vietnamNow.day);
  }

  Future<void> _loadOverview() async {
    final requestId = ++_overviewRequestId;
    setState(() => _overviewLoading = true);
    final result = await ApiService().getAdminOverview(
      period: _overviewPeriod,
      date: _overviewPeriod == 'all' ? null : _overviewDate,
    );
    if (!mounted || requestId != _overviewRequestId) return;
    setState(() {
      _overviewLoading = false;
      if (result != null) _overview = result;
      _overviewLoadFailed = result == null || !_hasMatchingPeriod(result);
    });
  }

  DateTime _periodStart(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    if (_overviewPeriod == 'week') {
      return day.subtract(Duration(days: day.weekday - DateTime.monday));
    }
    return DateTime.utc(day.year, day.month);
  }

  DateTime _periodEnd(DateTime date) => _overviewPeriod == 'week'
      ? _periodStart(date).add(const Duration(days: 6))
      : DateTime.utc(date.year, date.month + 1, 0);

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool _hasMatchingPeriod(Map<String, dynamic> overview) {
    if (_overviewPeriod == 'all') return true;
    final period = overview['period'];
    return period is Map &&
        period['type'] == _overviewPeriod &&
        period['start_date'] == _dateKey(_periodStart(_overviewDate)) &&
        period['end_date'] == _dateKey(_periodEnd(_overviewDate));
  }

  void _changeOverviewPeriod(String period) {
    setState(() {
      _overviewPeriod = period;
      final today = _vietnamToday();
      _overviewDate = period == 'all' ? today : _periodStart(today);
    });
    _loadOverview();
  }

  void _shiftOverviewPeriod(int delta) {
    if (_overviewPeriod == 'all') return;
    final candidate = _overviewPeriod == 'week'
        ? _overviewDate.add(Duration(days: delta * 7))
        : DateTime.utc(_overviewDate.year, _overviewDate.month + delta, 1);
    if (_periodStart(candidate).isAfter(_periodStart(_vietnamToday()))) return;
    setState(() => _overviewDate = candidate);
    _loadOverview();
  }

  Future<void> _logout() async {
    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
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
    ValueChanged<String> onChanged, {
    required double width,
  }) {
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
            .map(
              (e) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  e.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        items: options.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(
                  e.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _buildUsersTable(List<Map<String, dynamic>> users) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F6F7)),
              dataRowMinHeight: 56,
              dataRowMaxHeight: 62,
              horizontalMargin: 16,
              columnSpacing: 28,
              headingTextStyle: const TextStyle(
                color: _mutedInk,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              columns: const [
                DataColumn(label: Text('Tài khoản')),
                DataColumn(label: Text('Vai trò')),
                DataColumn(label: Text('Trạng thái')),
                DataColumn(label: Text('Giao dịch')),
                DataColumn(label: Text('Ví')),
                DataColumn(
                  label: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Thao tác'),
                  ),
                ),
              ],
              rows: users.map((u) {
                final role = u['role']?.toString() ?? 'user';
                final status = u['status']?.toString() ?? 'active';
                final admin = role == 'admin';
                final suspended = status == 'suspended';
                final marker =
                    u.containsKey('is_root_admin') ||
                    u.containsKey('isRootAdmin');
                final root =
                    u['is_root_admin'] == true ||
                    u['isRootAdmin'] == true ||
                    (admin && !marker);
                final edit = u['can_edit'] == true || u['canEdit'] == true;
                final suspend =
                    u['can_suspend'] == true || u['canSuspend'] == true;
                final changeRole =
                    u['can_change_role'] == true || u['canChangeRole'] == true;
                final delete =
                    u['can_delete'] == true || u['canDelete'] == true;
                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 260,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              u['full_name']?.toString() ?? 'Người dùng',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              u['email']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _mutedInk,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      _textChip(
                        root
                            ? 'Root admin'
                            : admin
                            ? 'Admin'
                            : 'User',
                        root ? _accent : _ink,
                      ),
                    ),
                    DataCell(
                      _statusChip(
                        suspended ? 'Tạm khóa' : 'Hoạt động',
                        suspended,
                      ),
                    ),
                    DataCell(
                      Text(
                        '${u['transaction_count'] ?? 0}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${u['wallet_count'] ?? 0}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 120,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (edit || suspend || changeRole)
                                PopupMenuButton<String>(
                                  tooltip: 'Thao tác tài khoản',
                                  onSelected: (v) {
                                    if (v == 'edit') _showUserForm(user: u);
                                    if (v == 'status') _toggleUserStatus(u);
                                    if (v == 'role') _toggleUserRole(u);
                                  },
                                  itemBuilder: (_) => [
                                    if (edit)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Sửa thông tin'),
                                      ),
                                    if (suspend)
                                      PopupMenuItem(
                                        value: 'status',
                                        child: Text(
                                          suspended
                                              ? 'Mở khóa tài khoản'
                                              : 'Khóa tài khoản',
                                        ),
                                      ),
                                    if (changeRole)
                                      PopupMenuItem(
                                        value: 'role',
                                        child: Text(
                                          admin
                                              ? 'Hạ quyền xuống User'
                                              : 'Cấp quyền Admin',
                                        ),
                                      ),
                                  ],
                                  icon: const Icon(Icons.more_horiz, size: 20),
                                ),
                              if (delete)
                                IconButton(
                                  tooltip: 'Xóa tài khoản',
                                  onPressed: () => _deleteUser(u),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Color(0xFF9D3C3C),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6F7),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
    ),
  );

  Widget _statusChip(String label, bool suspended) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: suspended ? const Color(0xFFB84A4A) : const Color(0xFF27805B),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(
          color: suspended ? const Color(0xFF9D3C3C) : const Color(0xFF276B4F),
          fontSize: 14,
        ),
      ),
    ],
  );

  Future<void> _showUserForm({Map<String, dynamic>? user}) async {
    final edit = user != null;
    final name = TextEditingController(
      text: user?['full_name']?.toString() ?? '',
    );
    final email = TextEditingController(text: user?['email']?.toString() ?? '');
    final password = TextEditingController();
    final key = GlobalKey<FormState>();
    var pending = false;
    String? error;
    final dialogRoute = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: Text(
            edit
                ? 'S\u1eeda t\u00e0i kho\u1ea3n'
                : 'Th\u00eam ng\u01b0\u1eddi d\u00f9ng',
          ),
          content: SizedBox(
            width: 420,
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'H\u1ecd v\u00e0 t\u00ean',
                    ),
                    validator: (v) =>
                        v == null ||
                            v.trim().isEmpty ||
                            v.trim().runes.length > 150
                        ? 'Nh\u1eadp h\u1ecd v\u00e0 t\u00ean (t\u1ed1i \u0111a 150 k\u00fd t\u1ef1)'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) =>
                        v == null ||
                            v.trim().length > 255 ||
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(v.trim())
                        ? 'Nh\u1eadp email h\u1ee3p l\u1ec7 (t\u1ed1i \u0111a 255 k\u00fd t\u1ef1)'
                        : null,
                  ),
                  if (!edit) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'M\u1eadt kh\u1ea9u',
                      ),
                      validator: (v) =>
                          v == null ||
                              v.runes.length < 10 ||
                              utf8.encode(v).length > 72
                          ? 'M\u1eadt kh\u1ea9u c\u1ea7n 10 k\u00fd t\u1ef1 v\u00e0 t\u1ed1i \u0111a 72 byte'
                          : null,
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFF9D3C3C)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: pending
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('H\u1ee7y'),
            ),
            FilledButton(
              onPressed: pending
                  ? null
                  : () async {
                      if (!(key.currentState?.validate() ?? false)) return;
                      update(() {
                        pending = true;
                        error = null;
                      });
                      final api = ApiService();
                      final result = edit
                          ? await api.updateAdminUserProfile(
                              user['id'].toString(),
                              fullName: name.text.trim(),
                              email: email.text.trim(),
                            )
                          : await api.createAdminUser(
                              fullName: name.text.trim(),
                              email: email.text.trim(),
                              password: password.text,
                            );
                      if (!context.mounted) return;
                      if (result.success) {
                        Navigator.pop(dialogContext, true);
                      } else {
                        update(() {
                          pending = false;
                          error = result.error ?? 'Kh\u00f4ng th\u1ec3 l\u01b0u t\u00e0i kho\u1ea3n';
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
              ),
              child: pending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      edit
                          ? 'L\u01b0u thay \u0111\u1ed5i'
                          : 'T\u1ea1o t\u00e0i kho\u1ea3n',
                    ),
            ),
          ],
        ),
      ),
    );
    final saved = await Navigator.of(context).push(dialogRoute);
    await dialogRoute.completed;
    name.dispose();
    email.dispose();
    password.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            edit
                ? '\u0110\u00e3 c\u1eadp nh\u1eadt t\u00e0i kho\u1ea3n'
                : '\u0110\u00e3 t\u1ea1o t\u00e0i kho\u1ea3n',
          ),
        ),
      );
      _loadAdminData();
    }
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
              onPressed: typedEmail.trim() == email
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1100;
        final page = _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
              )
            : TabBarView(
                controller: _tabController,
                physics: desktop ? const NeverScrollableScrollPhysics() : null,
                children: [
                  _buildOverviewTab(),
                  _buildUsersTab(),
                  _buildSystemTab(),
                ],
              );
        return Scaffold(
          backgroundColor: _paper,
          appBar: desktop
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  foregroundColor: _ink,
                  elevation: 0,
                  title: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FinWiseBrandMark(
                        size: 26,
                        fallbackIcon: Icons.account_balance_wallet_outlined,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'FinWise Admin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'L\u00e0m m\u1edbi s\u1ed1 li\u1ec7u',
                      onPressed: _loadAdminData,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: '\u0110\u0103ng xu\u1ea5t',
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    labelColor: _ink,
                    unselectedLabelColor: _mutedInk,
                    indicatorColor: const Color(0xFF4F46E5),
                    tabs: const [
                      Tab(text: 'Tổng quan'),
                      Tab(text: 'Người dùng'),
                      Tab(text: 'Hệ thống'),
                    ],
                  ),
                ),
          body: desktop
              ? Row(
                  children: [
                    SizedBox(
                      width: 232,
                      child: Material(
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(24, 28, 20, 28),
                              child: Row(
                                children: [
                                  FinWiseBrandMark(
                                    size: 28,
                                    fallbackIcon:
                                        Icons.account_balance_wallet_outlined,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'FinWise Admin',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: _ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Text(
                                'Quản trị',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _mutedInk,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            _desktopNavItem(
                              0,
                              Icons.speed_outlined,
                              'T\u1ed5ng quan & AI',
                            ),
                            _desktopNavItem(
                              1,
                              Icons.people_alt_outlined,
                              'Ng\u01b0\u1eddi D\u00f9ng',
                            ),
                            _desktopNavItem(
                              2,
                              Icons.settings_suggest_outlined,
                              'H\u1ea1 t\u1ea7ng',
                            ),
                            const Spacer(),
                            const Divider(height: 1, color: _line),
                            ListTile(
                              leading: const Icon(
                                Icons.logout,
                                size: 19,
                                color: _mutedInk,
                              ),
                              title: const Text(
                                '\u0110\u0103ng xu\u1ea5t',
                                style: TextStyle(color: _ink, fontSize: 14),
                              ),
                              onTap: _logout,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            height: 64,
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            color: Colors.white,
                            child: Row(
                              children: [
                                Text(
                                  _tabController.index == 0
                                      ? 'Admin · Tổng quan'
                                      : _tabController.index == 1
                                      ? 'Admin · Người dùng'
                                      : 'Admin · Hệ thống',
                                  style: const TextStyle(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w500,
                                    color: _ink,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip:
                                      'L\u00e0m m\u1edbi s\u1ed1 li\u1ec7u',
                                  onPressed: _loadAdminData,
                                  icon: const Icon(
                                    Icons.refresh,
                                    color: _mutedInk,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: page),
                        ],
                      ),
                    ),
                  ],
                )
              : page,
        );
      },
    );
  }

  Widget _desktopNavItem(int index, IconData icon, String label) {
    final selected = _tabController.index == index;
    return ListTile(
      selected: selected,
      selectedTileColor: const Color(0xFFF0F1FB),
      leading: Icon(
        icon,
        size: 19,
        color: selected ? const Color(0xFF4F46E5) : _mutedInk,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? _ink : _mutedInk,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
        ),
      ),
      onTap: () => setState(() => _tabController.index = index),
    );
  }

  // ==========================================
  // TAB 1: TỔNG QUAN & GIÁM SÁT AI
  // ==========================================
  Widget _buildOverviewTab() {
    final metrics = _overview?['metrics'] ?? {};
    final ai = _overview?['ai_service'] ?? {};
    final categories = _overviewLoading || _overviewLoadFailed
        ? const []
        : ((_overview?['category_distribution'] as List?) ?? []);

    final totalUsers = metrics['total_users'] ?? 0;
    final activeUsers = metrics['active_users'] ?? 0;
    final totalTxs = metrics['total_transactions'] ?? 0;
    final totalVolume = (metrics['total_volume'] as num?)?.toDouble() ?? 0.0;
    final periodLabel = switch (_overviewPeriod) {
      'week' => 'Tuần',
      'month' => 'Tháng',
      _ => 'Toàn thời gian',
    };
    final rangeLabel = _overviewPeriod == 'all'
        ? 'Tất cả thời gian'
        : '${DateFormat('dd/MM/yyyy').format(_periodStart(_overviewDate))} – '
              '${DateFormat('dd/MM/yyyy').format(_periodEnd(_overviewDate))}';
    final canGoForward =
        _overviewPeriod != 'all' &&
        _periodStart(_overviewDate).isBefore(_periodStart(_vietnamToday()));

    final aiStatusKnown = ai['status'] == 'online' || ai['status'] == 'offline';
    final isAiOnline = ai['status'] == 'online';

    return RefreshIndicator(
      onRefresh: _loadOverview,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('Tất cả')),
                          ButtonSegment(value: 'week', label: Text('Tuần')),
                          ButtonSegment(value: 'month', label: Text('Tháng')),
                        ],
                        selected: {_overviewPeriod},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) =>
                            _changeOverviewPeriod(selection.first),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Kỳ trước',
                            visualDensity: VisualDensity.compact,
                            onPressed: _overviewPeriod == 'all'
                                ? null
                                : () => _shiftOverviewPeriod(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text(
                            _overviewPeriod == 'all'
                                ? rangeLabel
                                : '$periodLabel · $rangeLabel',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Kỳ tiếp theo',
                            visualDensity: VisualDensity.compact,
                            onPressed: canGoForward
                                ? () => _shiftOverviewPeriod(1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_overviewLoadFailed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Không thể tải số liệu kỳ này'),
                        ),
                        TextButton(
                          onPressed: _loadOverview,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1040
                        ? 4
                        : constraints.maxWidth >= 620
                        ? 2
                        : 1;
                    final gap = 12.0;
                    final cardWidth =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: 'Người dùng',
                            value: '$totalUsers',
                            subtext: '$activeUsers đang hoạt động',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: _overviewPeriod == 'all'
                                ? 'Giao dịch'
                                : 'Giao dịch · $periodLabel',
                            value: _overviewLoading || _overviewLoadFailed
                                ? '—'
                                : '$totalTxs',
                            subtext: rangeLabel,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: _overviewPeriod == 'all'
                                ? 'Tổng dòng tiền'
                                : 'Dòng tiền · $periodLabel',
                            value: _overviewLoading || _overviewLoadFailed
                                ? '—'
                                : currencyFormat.format(totalVolume),
                            subtext: 'Thu + chi · $rangeLabel',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: 'Dịch vụ AI',
                            value: isAiOnline
                                ? 'Hoạt động'
                                : aiStatusKnown
                                ? 'Ngoại tuyến'
                                : 'Chưa rõ',
                            subtext: isAiOnline
                                ? 'Độ trễ ${ai['latency_ms'] ?? '—'} ms'
                                : 'Trạng thái do dịch vụ báo cáo',
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // AI Microservice Monitor Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.hub_outlined,
                                color: _mutedInk,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Giám sát dịch vụ AI',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _ink,
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
                              borderRadius: BorderRadius.circular(6),
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
                                      ? 'Đang hoạt động'
                                      : aiStatusKnown
                                      ? 'Ngoại tuyến'
                                      : 'Chưa có dữ liệu',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isAiOnline
                                        ? const Color(0xFF276B4F)
                                        : const Color(0xFF8A6415),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildAiModuleRow(
                        name: 'PhoBERT · phân loại chi tiêu',
                        desc: 'Gợi ý danh mục cho giao dịch',
                        isLoaded: ai['phobert_loaded'] == true
                            ? true
                            : ai['phobert_loaded'] == false
                            ? false
                            : null,
                      ),
                      const Divider(color: _line, height: 16),
                      _buildAiModuleRow(
                        name: 'LSTM · dự báo dòng tiền',
                        desc: 'Chu kỳ dự báo 7 ngày',
                        isLoaded: ai['lstm_loaded'] == true
                            ? true
                            : ai['lstm_loaded'] == false
                            ? false
                            : null,
                      ),
                      const Divider(color: _line, height: 16),
                      _buildAiModuleRow(
                        name: 'EasyOCR · đọc hóa đơn',
                        desc: 'Nhận dạng tiếng Việt và tiếng Anh',
                        isLoaded: ai['ocr_loaded'] == true
                            ? true
                            : ai['ocr_loaded'] == false
                            ? false
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Text(
                                'Thiết bị: ${ai['device'] ?? 'Chưa có dữ liệu'}${ai['gpu_name'] == null ? '' : ' · ${ai['gpu_name']}'}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: _mutedInk,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              'Thời gian phản hồi: ${ai['latency_ms'] ?? '—'} ms',
                              style: const TextStyle(
                                fontSize: 14,
                                color: _ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  _overviewPeriod == 'all'
                      ? 'Phân bổ chi tiêu'
                      : 'Phân bổ chi tiêu · $periodLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 20,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tỷ trọng theo danh mục · $rangeLabel',
                  style: const TextStyle(fontSize: 14, color: _mutedInk),
                ),
                const SizedBox(height: 12),

                if (categories.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        _overviewLoading
                            ? 'Đang tải dữ liệu giao dịch…'
                            : _overviewLoadFailed
                            ? 'Không thể tải phân bổ giao dịch kỳ này'
                            : 'Chưa có giao dịch chi tiêu nào để phân tích',
                        style: const TextStyle(color: _mutedInk, fontSize: 14),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _line),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: categories.map((cat) {
                        final percent =
                            (cat['percent'] as num?)?.toDouble() ?? 0.0;
                        final amount =
                            (cat['amount'] as num?)?.toDouble() ?? 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      cat['name']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: _ink,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    currencyFormat.format(amount),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: _ink,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${cat['count'] ?? 0} giao dịch',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: _mutedInk,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${percent.toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: _mutedInk,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: (percent / 100).clamp(0.0, 1.0),
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  _accent,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                minHeight: 8,
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
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, color: _mutedInk)),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              color: _ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            subtext,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: _mutedInk),
          ),
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
              ? const Color(0xFF27805B)
              : isLoaded == false
              ? const Color(0xFF9D3C3C)
              : _mutedInk,
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
                  color: _ink,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$desc · ${isLoaded == true
                    ? 'Đã tải'
                    : isLoaded == false
                    ? 'Chưa tải'
                    : 'Chưa có dữ liệu'}',
                style: const TextStyle(color: _mutedInk, fontSize: 14),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: RefreshIndicator(
                onRefresh: _loadUsers,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: LayoutBuilder(
                            builder: (context, inner) => Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: inner.maxWidth >= 860
                                      ? inner.maxWidth - 555
                                      : inner.maxWidth,
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (value) {
                                      setState(() {
                                        _searchQuery = value;
                                        _currentPage = 1;
                                      });
                                      _searchDebounce?.cancel();
                                      _searchDebounce = Timer(
                                        const Duration(milliseconds: 350),
                                        _loadUsers,
                                      );
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Tìm theo tên hoặc email',
                                      labelText: 'Tìm tài khoản',
                                      prefixIcon: const Icon(
                                        Icons.search,
                                        size: 20,
                                      ),
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: _line,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: _line,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
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
                                    _loadUsers();
                                  },
                                  width: 150,
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
                                    _loadUsers();
                                  },
                                  width: 185,
                                ),
                                SizedBox(
                                  width: 184,
                                  child: FilledButton.icon(
                                    onPressed: () => _showUserForm(),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Thêm người dùng'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: _line),
                        if (_usersLoadFailed)
                          SizedBox(
                            height: 144,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Không thể tải danh sách tài khoản',
                                  ),
                                  TextButton(
                                    onPressed: _loadUsers,
                                    child: const Text('Thử lại'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (_filteredUsers.isEmpty)
                          SizedBox(
                            height: 144,
                            child: Center(
                              child: Text(
                                _users.isEmpty
                                    ? 'Chưa có tài khoản người dùng'
                                    : 'Không có tài khoản khớp bộ lọc',
                                style: const TextStyle(
                                  color: _mutedInk,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        else if (constraints.maxWidth >= 720)
                          _buildUsersTable(_filteredUsers)
                        else
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < _filteredUsers.length;
                                  i++
                                ) ...[
                                  if (i > 0) const SizedBox(height: 8),
                                  _buildCompactUser(_filteredUsers[i]),
                                ],
                              ],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: _line)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '$_totalUsers tài khoản  ·  Trang $_currentPage/${((_totalUsers - 1) ~/ _perPage + 1).clamp(1, 99999)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: _mutedInk,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Trang trước',
                                onPressed: _currentPage > 1
                                    ? () {
                                        setState(() => _currentPage--);
                                        _loadUsers();
                                      }
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                tooltip: 'Trang sau',
                                onPressed: _currentPage * _perPage < _totalUsers
                                    ? () {
                                        setState(() => _currentPage++);
                                        _loadUsers();
                                      }
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactUser(Map<String, dynamic> user) {
    final role = user['role']?.toString() ?? 'user';
    final status = user['status']?.toString() ?? 'active';
    final admin = role == 'admin';
    final suspended = status == 'suspended';
    final hasRootMarker =
        user.containsKey('is_root_admin') || user.containsKey('isRootAdmin');
    final root =
        user['is_root_admin'] == true ||
        user['isRootAdmin'] == true ||
        (admin && !hasRootMarker);
    final edit = user['can_edit'] == true || user['canEdit'] == true;
    final suspend = user['can_suspend'] == true || user['canSuspend'] == true;
    final changeRole =
        user['can_change_role'] == true || user['canChangeRole'] == true;
    final delete = user['can_delete'] == true || user['canDelete'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['full_name']?.toString() ??
                          'Ng\u01b0\u1eddi D\u00f9ng',
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      user['email']?.toString() ?? '',
                      style: const TextStyle(color: _mutedInk, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: edit || suspend || changeRole || delete,
                onSelected: (value) {
                  if (value == 'edit') _showUserForm(user: user);
                  if (value == 'status') _toggleUserStatus(user);
                  if (value == 'role') _toggleUserRole(user);
                  if (value == 'delete') _deleteUser(user);
                },
                itemBuilder: (_) => [
                  if (edit)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('S\u1eeda th\u00f4ng tin'),
                    ),
                  if (suspend)
                    PopupMenuItem(
                      value: 'status',
                      child: Text(
                        suspended
                            ? 'M\u1edf kh\u00f3a t\u00e0i kho\u1ea3n'
                            : 'Kh\u00f3a t\u00e0i kho\u1ea3n',
                      ),
                    ),
                  if (changeRole)
                    PopupMenuItem(
                      value: 'role',
                      child: Text(
                        admin
                            ? 'H\u1ea1 quy\u1ec1n xu\u1ed1ng User'
                            : 'C\u1ea5p quy\u1ec1n Admin',
                      ),
                    ),
                  if (delete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('X\u00f3a t\u00e0i kho\u1ea3n'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _textChip(
                root
                    ? 'Root admin'
                    : admin
                    ? 'Admin'
                    : 'User',
                root ? _accent : _ink,
              ),
              _statusChip(suspended ? 'Tạm khóa' : 'Hoạt động', suspended),
              Text(
                '${user['transaction_count'] ?? 0} giao dịch  ·  ${user['wallet_count'] ?? 0} ví',
                style: const TextStyle(color: _mutedInk, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: HẠ TẦNG & CẤU HÌNH HỆ THỐNG
  // ==========================================
  Widget _buildSystemTab() {
    final ai = _overview?['ai_service'] ?? {};
    bool? loaded(String key) => ai[key] == true
        ? true
        : ai[key] == false
        ? false
        : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final wide = availableWidth >= 1000;
              final gap = 16.0;
              final primaryWidth = wide
                  ? (availableWidth - gap) * .66
                  : availableWidth;
              final sideWidth = wide
                  ? (availableWidth - gap) - primaryWidth
                  : availableWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: primaryWidth,
                    child: _buildInfoSection(
                      title: 'Dịch vụ AI',
                      items: [
                        _buildAiModuleRow(
                          name: 'PhoBERT · phân loại chi tiêu',
                          desc: 'Trạng thái mô-đun do dịch vụ báo cáo',
                          isLoaded: loaded('phobert_loaded'),
                        ),
                        const Divider(color: _line, height: 24),
                        _buildAiModuleRow(
                          name: 'LSTM · dự báo dòng tiền',
                          desc: 'Chu kỳ dự báo 7 ngày',
                          isLoaded: loaded('lstm_loaded'),
                        ),
                        const Divider(color: _line, height: 24),
                        _buildAiModuleRow(
                          name: 'EasyOCR · đọc hóa đơn',
                          desc: 'Nhận dạng tiếng Việt và tiếng Anh',
                          isLoaded: loaded('ocr_loaded'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: sideWidth,
                    child: Column(
                      children: [
                        _buildInfoSection(
                          title: 'Kết nối và xác thực',
                          items: [
                            _buildInfoRow('API', ApiService().baseUrl),
                            _buildInfoRow('Máy chủ', 'Node.js / Express'),
                            _buildInfoRow(
                              'Cơ sở dữ liệu',
                              'Supabase / PostgreSQL',
                            ),
                            _buildInfoRow('Đăng nhập', 'Bcrypt và JWT'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoSection(
                          title: 'Quyền truy cập',
                          items: [
                            _buildInfoRow(
                              'Trang quản trị',
                              'Tài khoản có role admin',
                            ),
                            _buildInfoRow(
                              'Tài khoản gốc',
                              'Không thể xóa hoặc tạm khóa',
                            ),
                            _buildInfoRow(
                              'Dữ liệu',
                              'Số liệu tổng hợp, không gồm giao dịch riêng tư',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<Widget> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 17,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: _mutedInk),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
