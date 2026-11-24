import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
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
  static const _ink = Color(0xFF17212B);
  static const _mutedInk = Color(0xFF65717D);
  static const _paper = Color(0xFFF4F6F7);
  static const _line = Color(0xFFE1E6E9);

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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFEDF0F2)),
            dataRowMinHeight: 52,
            dataRowMaxHeight: 58,
            horizontalMargin: 14,
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('T\u00e0i kho\u1ea3n')),
              DataColumn(label: Text('Vai tr\u00f2')),
              DataColumn(label: Text('Tr\u1ea1ng th\u00e1i')),
              DataColumn(label: Text('Giao d\u1ecbch')),
              DataColumn(label: Text('V\u00ed')),
              DataColumn(label: Text('Thao t\u00e1c')),
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
              final delete = u['can_delete'] == true || u['canDelete'] == true;
              return DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 250,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            u['full_name']?.toString() ??
                                'Ng\u01b0\u1eddi D\u00f9ng',
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
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      root
                          ? 'Root admin'
                          : admin
                          ? 'Admin'
                          : 'User',
                      style: TextStyle(
                        color: root ? const Color(0xFF4F46E5) : _ink,
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: suspended
                                ? const Color(0xFFB84A4A)
                                : const Color(0xFF27805B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          suspended
                              ? 'T\u1ea1m kh\u00f3a'
                              : 'Ho\u1ea1t \u0111\u1ed9ng',
                          style: TextStyle(
                            color: suspended
                                ? const Color(0xFF9D3C3C)
                                : const Color(0xFF276B4F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text('${u['transaction_count'] ?? 0}')),
                  DataCell(Text('${u['wallet_count'] ?? 0}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (edit || suspend || changeRole)
                          PopupMenuButton<String>(
                            tooltip: 'Thao t\u00e1c t\u00e0i kho\u1ea3n',
                            onSelected: (v) {
                              if (v == 'edit') _showUserForm(user: u);
                              if (v == 'status') _toggleUserStatus(u);
                              if (v == 'role') _toggleUserRole(u);
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
                            ],
                            icon: const Icon(Icons.more_horiz, size: 20),
                          ),
                        if (delete)
                          IconButton(
                            tooltip: 'X\u00f3a t\u00e0i kho\u1ea3n',
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
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

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
                  title: const Text(
                    'FinWise',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
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
                      Tab(
                        icon: Icon(Icons.speed, size: 19),
                        text: 'T\u1ed5ng quan & AI',
                      ),
                      Tab(
                        icon: Icon(Icons.people_alt_outlined, size: 19),
                        text: 'Ng\u01b0\u1eddi D\u00f9ng',
                      ),
                      Tab(
                        icon: Icon(Icons.settings_suggest_outlined, size: 19),
                        text: 'H\u1ea1 t\u1ea7ng',
                      ),
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
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: Color(0xFF4F46E5),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'FinWise',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: _ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Text(
                                'Qu\u1ea3n tr\u1ecb',
                                style: TextStyle(
                                  fontSize: 11,
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
                                      ? 'T\u1ed5ng quan & AI'
                                      : _tabController.index == 1
                                      ? 'Ng\u01b0\u1eddi D\u00f9ng'
                                      : 'H\u1ea1 t\u1ea7ng',
                                  style: const TextStyle(
                                    fontSize: 18,
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
                    color: Colors.white,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [],
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
                                color: _mutedInk,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Giám Sát AI Microservices',
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
                                      ? 'ONLINE'
                                      : aiStatusKnown
                                      ? 'OFFLINE'
                                      : 'UNKNOWN',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
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
                        name: 'PhoBERT NLP Classifier',
                        desc: 'Nhận diện & tự động gán nhãn 10 danh mục chi tiêu tiếng Việt',
                        isLoaded: ai['phobert_loaded'] == true
                            ? true
                            : ai['phobert_loaded'] == false
                            ? false
                            : null,
                      ),
                      const Divider(color: _line, height: 16),
                      _buildAiModuleRow(
                        name: 'Time-Series LSTM Forecaster',
                        desc: 'Dự báo xu hướng tài chính & dòng tiền 7 ngày tiếp theo',
                        isLoaded: ai['lstm_loaded'] == true
                            ? true
                            : ai['lstm_loaded'] == false
                            ? false
                            : null,
                      ),
                      const Divider(color: _line, height: 16),
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
                          color: const Color(0xFFF4F6F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Thiết bị thực thi: ${ai['device'] ?? 'Chưa có dữ liệu'} (${ai['gpu_name'] ?? 'GPU chưa báo cáo'})',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _mutedInk,
                              ),
                            ),
                            Text(
                              'Độ trễ: ${ai['latency_ms'] ?? '—'}ms',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF276B4F),
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
                style: const TextStyle(color: _mutedInk, fontSize: 12),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth > 700
                      ? 300
                      : constraints.maxWidth,
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
                        _loadAdminData,
                      );
                    },
                    decoration: InputDecoration(
                      hintText: 'T\u00ecm theo t\u00ean ho\u1eb7c email',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _line),
                      ),
                    ),
                  ),
                ),
                _filterDropdown(
                  'Vai tr\u00f2',
                  _roleFilter,
                  const {
                    'all': 'T\u1ea5t c\u1ea3 vai tr\u00f2',
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
                  width: 170,
                ),
                _filterDropdown(
                  'Tr\u1ea1ng th\u00e1i',
                  _statusFilter,
                  const {
                    'all': 'T\u1ea5t c\u1ea3 tr\u1ea1ng th\u00e1i',
                    'active': 'Ho\u1ea1t \u0111\u1ed9ng',
                    'suspended': 'T\u1ea1m kh\u00f3a',
                  },
                  (v) {
                    setState(() {
                      _statusFilter = v;
                      _currentPage = 1;
                    });
                    _loadAdminData();
                  },
                  width: 185,
                ),
                FilledButton.icon(
                  onPressed: () => _showUserForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Th\u00eam ng\u01b0\u1eddi d\u00f9ng'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                              const Text(
                                'Kh\u00f4ng th\u1ec3 t\u1ea3i danh s\u00e1ch t\u00e0i kho\u1ea3n',
                              ),
                              TextButton(
                                onPressed: _loadAdminData,
                                child: const Text('Th\u1eed l\u1ea1i'),
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
                                ? 'Ch\u01b0a c\u00f3 t\u00e0i kho\u1ea3n ng\u01b0\u1eddi d\u00f9ng'
                                : 'Kh\u00f4ng c\u00f3 t\u00e0i kho\u1ea3n kh\u1edbp b\u1ed9 l\u1ecdc',
                            style: const TextStyle(color: _mutedInk),
                          ),
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 720
                        ? _buildUsersTable(_filteredUsers)
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredUsers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _buildCompactUser(_filteredUsers[index]),
                          ),
                  ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: _line)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$_totalUsers t\u00e0i kho\u1ea3n  \u00b7  Trang $_currentPage/${((_totalUsers - 1) ~/ _perPage + 1).clamp(1, 99999)}',
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Trang tr\u01b0\u1edbc',
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

  Widget _buildCompactUser(Map<String, dynamic> user) {
    final role = user['role']?.toString() ?? 'user';
    final status = user['status']?.toString() ?? 'active';
    final admin = role == 'admin';
    final suspended = status == 'suspended';
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
          Row(
            children: [
              Text(
                admin ? 'Admin' : 'User',
                style: const TextStyle(color: _ink),
              ),
              const SizedBox(width: 16),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: suspended
                      ? const Color(0xFFB84A4A)
                      : const Color(0xFF27805B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                suspended ? 'T\u1ea1m kh\u00f3a' : 'Ho\u1ea1t \u0111\u1ed9ng',
                style: TextStyle(
                  color: suspended
                      ? const Color(0xFF9D3C3C)
                      : const Color(0xFF276B4F),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${user['transaction_count'] ?? 0} giao d\u1ecbch  \u00b7  ${user['wallet_count'] ?? 0} v\u00ed',
                style: const TextStyle(color: _mutedInk, fontSize: 12),
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

  Widget _buildInfoSection({
    required String title,
    required List<Widget> items,
  }) {
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
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1E293B),
            ),
          ),
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
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
