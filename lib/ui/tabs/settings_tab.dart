import 'package:flutter/material.dart';
import '../folder_selection_screen.dart';
import 'dart:io';
import '../../services/notification_service.dart';
import '../../services/theme_service.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Profile Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primaryContainer,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(Icons.person, size: 30, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ผู้ใช้งานทั่วไป', // User name (Placeholder)
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Kanit',
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Basic Plan',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Kanit',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () {}, // Edit profile action
                      tooltip: "แก้ไขโปรไฟล์",
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: AnimatedBuilder(
                  animation: ThemeService(),
                  builder: (context, _) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        // Section: General
                        _buildAnimatedItem(
                          delay: 100,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(context, "ทั่วไป"),
                              _buildSettingsTile(
                                context,
                                title: "โฟลเดอร์สแกน",
                                subtitle: "เลือกอัลบั้มรูปสลิป",
                                icon: Icons.folder_open_rounded,
                                color: Colors.blueAccent,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const FolderSelectionScreen()),
                                  );
                                },
                              ),
                              _buildSettingsTile(
                                context,
                                title: "Auto-track",
                                subtitle: "บันทึกจากแจ้งเตือนธนาคาร",
                                icon: Icons.notifications_active_rounded,
                                color: Colors.orangeAccent,
                                onTap: () {},
                                trailing: StatefulBuilder(
                                  builder: (context, setState) {
                                    final service = NotificationService();
                                    return Switch.adaptive(
                                      value: service.isListening, 
                                      activeColor: colorScheme.primary,
                                      onChanged: (val) async {
                                        if (Platform.isIOS) {
                                          await showDialog(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text("Not Supported"),
                                              content: const Text("ฟีเจอร์นี้ไม่รองรับบน iOS เนื่องจากข้อจำกัดด้านความเป็นส่วนตัวของ Apple"),
                                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("ตกลง"))],
                                            ),
                                          );
                                          return;
                                        }

                                        if (val) {
                                          // Enable Flow
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text("Privacy Warning"),
                                              content: const Text("ฟีเจอร์นี้จะทำการอ่านแจ้งเตือนจากแอปธนาคารเพื่อบันทึกรายการอัตโนมัติ\n\nข้อมูลจะถูกบันทึกในเครื่องเท่านั้น ไม่มีการส่งออกภายนอก"),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ยกเลิก")),
                                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("ยอมรับ")),
                                              ],
                                            ),
                                          );

                                          if (confirm == true) {
                                            final granted = await service.requestPermission();
                                            // Since requestPermission just opens settings, we should check again or assume they might have granted it.
                                            // A better UX would be to wait for lifecycle resume, but for now:
                                            if (granted) {
                                              // Wait a bit for user to potentially toggle it (though they are in another app)
                                              // Actually, we can't wait here.
                                              // We just try to start. If it fails, it fails.
                                              await service.startListening();
                                            }
                                          }
                                        } else {
                                          // Disable
                                          await service.stopListening();
                                        }
                                        setState(() {}); // Rebuild switch
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),

                        // Section: Appearance
                        _buildAnimatedItem(
                          delay: 200,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(context, "การแสดงผล"),
                              // Theme Mode
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildModeButton(
                                        context,
                                        label: "สว่าง",
                                        icon: Icons.light_mode_rounded,
                                        mode: ThemeMode.light,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildModeButton(
                                        context,
                                        label: "มืด",
                                        icon: Icons.dark_mode_rounded,
                                        mode: ThemeMode.dark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Color Palette (Horizontal Scroll)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "ธีมสีหลัก", 
                                            style: TextStyle(
                                              fontFamily: 'Kanit', 
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onSurface
                                            )
                                          ),
                                          GestureDetector(
                                            onTap: () => ThemeService().setPastelMode(!ThemeService().isPastelMode),
                                            child: Text(
                                              ThemeService().isPastelMode ? "พาสเทล" : "สดใส",
                                              style: TextStyle(
                                                fontFamily: 'Kanit',
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.primary
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 50,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        itemCount: ThemeService().currentPalette.length,
                                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                                        itemBuilder: (context, index) {
                                          final color = ThemeService().currentPalette[index];
                                          final isSelected = ThemeService().currentThemeColorIndex == index;
                                          return GestureDetector(
                                            onTap: () => ThemeService().setThemeColor(index),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              width: isSelected ? 50 : 40,
                                              height: isSelected ? 50 : 40,
                                              decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected ? colorScheme.onSurface : Colors.transparent,
                                                  width: 2,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: color.withOpacity(0.4),
                                                    blurRadius: isSelected ? 8 : 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: isSelected
                                                  ? Icon(Icons.check, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                                                  : null,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Section: Security
                        _buildAnimatedItem(
                          delay: 300,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(context, "ความปลอดภัย"),
                              _buildSettingsTile(
                                context,
                                title: "ล็อคแอปพลิเคชัน",
                                subtitle: "Face ID / Touch ID",
                                icon: Icons.fingerprint_rounded,
                                color: Colors.redAccent,
                                onTap: () {},
                                trailing: Switch.adaptive(
                                  value: false, 
                                  onChanged: (val) {}, 
                                  activeColor: colorScheme.primary
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Section: Data
                        _buildAnimatedItem(
                          delay: 400,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(context, "ข้อมูล"),
                              _buildSettingsTile(
                                context,
                                title: "ส่งออกข้อมูล",
                                subtitle: "CSV / Excel",
                                icon: Icons.ios_share_rounded,
                                color: Colors.green,
                                onTap: () {},
                              ),
                              _buildSettingsTile(
                                context,
                                title: "สำรองข้อมูล",
                                subtitle: "Backup ไปยัง Cloud",
                                icon: Icons.cloud_upload_rounded,
                                color: Colors.purple,
                                onTap: () {},
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 48), // Bottom padding
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedItem({required int delay, required Widget child}) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, double value, _) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontFamily: 'Kanit',
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
    bool comingSoon = false,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Kanit',
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Kanit',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (comingSoon)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text("เร็วๆนี้", style: TextStyle(fontSize: 10, fontFamily: 'Kanit', color: theme.colorScheme.onSurfaceVariant)),
                  )
                else if (trailing != null)
                  trailing
                else
                  Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(BuildContext context, {required String label, required IconData icon, required ThemeMode mode}) {
    final isSelected = ThemeService().currentThemeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: () => ThemeService().setThemeMode(mode),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.transparent : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Kanit',
                fontWeight: FontWeight.bold,
                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
