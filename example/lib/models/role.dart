/// Role model — belongsToMany target on User.
library;

import 'package:drift/drift.dart' show TableInfo;
import 'package:eloquent_flutter/eloquent_flutter.dart';

import '../database.dart';
import '../registry.dart';

class Role extends Model<Role, RoleRow> {
  Role(super.data);

  @override
  TableInfo<Roles, RoleRow> get $table => AppRegistry.roles;

  @override
  Role $wrap(RoleRow data) => Role(data);

  @override
  Map<String, dynamic> toMap() => {
        'id': $data.id,
        'name': $data.name,
      };

  static final ModelQuery<Role, RoleRow> _q = ModelQuery<Role, RoleRow>(
    table: AppRegistry.roles,
    creator: Role.new,
  );

  static Future<List<Role>> all() => _q.all();
  static Future<Role?> find(Object id) => _q.find(id);
  static Future<Role> findOrFail(Object id) => _q.findOrFail(id);
  static Future<Role?> first({String? orderBy}) => _q.first(orderBy: orderBy);
  static Future<int> count() => _q.count();
  static Future<bool> exists() => _q.exists();
  static Stream<List<Role>> watch() => _q.watch();
  static Future<Role> create(Map<String, dynamic> values) => _q.create(values);
  static QueryBuilder<Role, RoleRow> where(
    String c, [
    Object? v,
    String op = '=',
  ]) =>
      _q.where(c, v, op);
  static QueryBuilder<Role, RoleRow> query() => _q.query();
}
