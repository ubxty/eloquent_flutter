/// User model — demonstrates the forwarding-static pattern, relationships,
/// observer registration, and timestamps.
library;

import 'package:drift/drift.dart' show TableInfo;
import 'package:eloquent_flutter/eloquent_flutter.dart';

import '../database.dart';
import '../registry.dart';
import 'post.dart';
import 'profile.dart';
import 'role.dart';

class User extends Model<User, UserRow> {
  User(super.data);

  @override
  TableInfo<Users, UserRow> get $table => AppRegistry.users;

  @override
  User $wrap(UserRow data) => User(data);

  @override
  Map<String, dynamic> toMap() => {
        'id': $data.id,
        'email': $data.email,
        'name': $data.name,
        'active': $data.active,
        'created_at': $data.createdAt,
        'updated_at': $data.updatedAt,
      };

  // ===== Relationships =====

  HasMany<Post, PostRow> posts() => HasMany<Post, PostRow>(
        local: this,
        relatedTable: AppRegistry.posts,
        foreignKey: 'user_id',
        creator: Post.new,
      );

  HasOne<Profile, ProfileRow> profile() => HasOne<Profile, ProfileRow>(
        local: this,
        relatedTable: AppRegistry.profiles,
        foreignKey: 'user_id',
        creator: Profile.new,
      );

  BelongsToMany<Role, RoleRow> roles() => BelongsToMany<Role, RoleRow>(
        local: this,
        relatedTable: AppRegistry.roles,
        creator: Role.new,
        pivotTable: 'role_users',
        foreignPivotKey: 'user_id',
        relatedPivotKey: 'role_id',
      );

  @override
  Map<String, Relationship<dynamic>> get $relations => {
        'posts': posts(),
        'profile': profile(),
        'roles': roles(),
      };

  // ===== Observer =====

  @override
  ObserverSet get $observers => ObserverSet(
        creating: (u) {
          // Reject users without an @ in their email.
          return (u.toMap()['email'] as String).contains('@');
        },
        created: (u) {
          // ignore: avoid_print
          print('User created: id=${u.toMap()['id']}');
        },
      );

  // ===== Forwarding statics =====

  static final ModelQuery<User, UserRow> _q = ModelQuery<User, UserRow>(
    table: AppRegistry.users,
    creator: User.new,
    primaryKey: 'id',
  );

  static Future<List<User>> all() => _q.all();
  static Future<User?> find(Object id) => _q.find(id);
  static Future<User> findOrFail(Object id) => _q.findOrFail(id);
  static Future<User?> first({String? orderBy}) => _q.first(orderBy: orderBy);
  static Future<int> count() => _q.count();
  static Future<bool> exists() => _q.exists();
  static Stream<List<User>> watch() => _q.watch();
  static Future<User> create(Map<String, dynamic> values) => _q.create(values);
  static Future<int> createMany(List<Map<String, dynamic>> rows) =>
      _q.createMany(rows);
  static QueryBuilder<User, UserRow> where(
    String c, [
    Object? v,
    String op = '=',
  ]) =>
      _q.where(c, v, op);
  static QueryBuilder<User, UserRow> query() => _q.query();
}
