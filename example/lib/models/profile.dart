/// Profile model — hasOne target on User.
library;

import 'package:drift/drift.dart' show TableInfo;
import 'package:eloquent_flutter/eloquent_flutter.dart';

import '../database.dart';
import '../registry.dart';

class Profile extends Model<Profile, ProfileRow> {
  Profile(super.data);

  @override
  TableInfo<Profiles, ProfileRow> get $table => AppRegistry.profiles;

  @override
  Profile $wrap(ProfileRow data) => Profile(data);

  @override
  Map<String, dynamic> toMap() => {
        'id': $data.id,
        'user_id': $data.userId,
        'bio': $data.bio,
      };

  static final ModelQuery<Profile, ProfileRow> _q =
      ModelQuery<Profile, ProfileRow>(
    table: AppRegistry.profiles,
    creator: Profile.new,
  );

  static Future<List<Profile>> all() => _q.all();
  static Future<Profile?> find(Object id) => _q.find(id);
  static Future<Profile> findOrFail(Object id) => _q.findOrFail(id);
  static Future<Profile?> first({String? orderBy}) => _q.first(orderBy: orderBy);
  static Future<int> count() => _q.count();
  static Future<bool> exists() => _q.exists();
  static Stream<List<Profile>> watch() => _q.watch();
  static Future<Profile> create(Map<String, dynamic> values) =>
      _q.create(values);
  static QueryBuilder<Profile, ProfileRow> where(
    String c, [
    Object? v,
    String op = '=',
  ]) =>
      _q.where(c, v, op);
  static QueryBuilder<Profile, ProfileRow> query() => _q.query();
}
