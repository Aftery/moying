import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model/actor.dart';
import 'model/book.dart';
import 'model/movie.dart';
import 'model/stats.dart';
import 'model/user_profile.dart';

/// 跨模块门面契约 —— 其他业务模块（stats / profile / sync）对书影库的
/// 唯一依赖点，只暴露它们实际消费的成员，不暴露增删改与内部缓存。
///
/// 架构动机（同级引用清零）：stats/profile/sync 此前直接 import
/// `library/view_model/library_provider.dart`，形成 6 处同级依赖。
/// 改为本接口后，消费方只认识 [LibraryFacade]；`LibraryProvider`
/// 负责实现，装配时在 app 层以 `ListenableProvider<LibraryFacade>`
/// 注册**同一实例**，`context.select` 的响应性与之前完全一致。
///
/// `implements Listenable` 是为了满足 `ListenableProvider<T extends
/// Listenable?>` 的类型约束（真身是 ChangeNotifier）——并非要求消费方
/// 直接监听，订阅仍走 Provider 的 select。
abstract class LibraryFacade implements Listenable {
  // ==================== 只读数据（select 订阅） ====================

  /// 全量书库
  List<Book> get books;

  /// 全量电影
  List<Movie> get movieList;

  /// 全量演员
  List<Actor> get actors;

  /// 阅读统计聚合
  BookStats get bookStats;

  /// 观影统计聚合
  MovieStats get movieStats;

  /// 想读书籍
  List<Book> get planToReadBooks;

  /// 仪表盘阅读列表（读完优先，最多 6 本）
  List<Book> get readingList;

  /// 在读书籍（最多 2 本）
  List<Book> get currentlyReadingBooks;

  /// 想看电影（前 2 部）
  List<Movie> get upcomingMovies;

  /// 用户档案
  UserProfile get userProfile;

  /// 主题偏好（'dark' / 'light' / 'system'）
  String get themeMode;

  // ==================== 档案编辑（profile 模块用） ====================

  /// 更新档案（含主题偏好持久化）
  Future<void> updateProfile(UserProfile updated);

  /// 复制图片进 images/，返回 MediaRef.localFile 相对名
  Future<String?> attachImage(File source, String entryId);

  /// 唤起系统选图（无 picker 时抛出由调用方处理）
  Future<File?> pickImageFile();

  /// 是否可唤起系统选图
  bool get canPickImage;

  /// 切换主题偏好
  Future<void> setThemeMode(String mode);

  // ==================== 同步生命周期（sync 模块用） ====================

  /// 冲刷未落盘的合并写
  Future<void> flush();

  /// 云端恢复后从存储重载
  Future<void> reloadFromStore();
}
