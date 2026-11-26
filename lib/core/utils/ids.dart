import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId([String prefix = 'id']) =>
    '${prefix}_${_uuid.v4().replaceAll('-', '').substring(0, 12)}';
