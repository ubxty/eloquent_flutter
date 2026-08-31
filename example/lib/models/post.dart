/// Post model — hasMany target on User.
library;

import 'package:drift/drift.dart' show TableInfo;
import 'package:eloquent_flutter/eloquent_flutter.dart';

import '../database.dart';
import '../registry.dart';
import 'user.dart';

class Post extends Model<Post, PostRow> {
  Post(super.data);

  @override
  TableInfo<Posts, PostRow> get $table => AppRegistry.posts;

  @override
  Post $wrap(PostRow data) => Post(data);

  @override
  Map<String, dynamic> toMap() => {
        'id': $data.id,
        'user_id': $data.userId,
        'title': $data.title,
        'body': $data.body,
      };

  BelongsTo<User, UserRow> user() => BelongsTo<User, UserRow>(
        local: this,
        relatedTable: AppRegistry.users,
        foreignKey: 'user_id',
        creator: User.new,
      );

  @override
  Map<String, Relationship<dynamic>> get $relations => {
        'user': user(),
      };

  static final ModelQuery<Post, PostRow> _q = ModelQuery<Post, PostRow>(
    table: AppRegistry.posts,
    creator: Post.new,
  );

  static Future<List<Post>> all() => _q.all();
  static Future<Post?> find(Object id) => _q.find(id);
  static Future<Post> findOrFail(Object id) => _q.findOrFail(id);
  static Future<Post?> first({String? orderBy}) => _q.first(orderBy: orderBy);
  static Future<int> count() => _q.count();
  static Future<bool> exists() => _q.exists();
  static Stream<List<Post>> watch() => _q.watch();
  static Future<Post> create(Map<String, dynamic> values) => _q.create(values);
  static QueryBuilder<Post, PostRow> where(
    String c, [
    Object? v,
    String op = '=',
  ]) =>
      _q.where(c, v, op);
  static QueryBuilder<Post, PostRow> query() => _q.query();
}
