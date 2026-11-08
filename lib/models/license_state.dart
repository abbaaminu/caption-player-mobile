import 'package:flutter/foundation.dart';

/// Immutable activation state persisted between launches.
@immutable
class LicenseState {
  const LicenseState({this.key, this.isSubscribed = false});

  /// Tolerates missing keys and values written by older app versions.
  factory LicenseState.fromJson(Map<String, dynamic> json) {
    final rawKey = json['key'];
    final normalizedKey = rawKey is String ? rawKey.trim() : '';

    return LicenseState(
      key: normalizedKey.isEmpty ? null : normalizedKey,
      isSubscribed: json['subscribed'] == true,
    );
  }

  final String? key;
  final bool isSubscribed;

  /// A subscription is only usable when it is paired with a key.
  bool get isValid => isSubscribed && (key?.isNotEmpty ?? false);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'subscribed': isSubscribed,
  };

  LicenseState copyWith({String? key, bool? isSubscribed}) {
    return LicenseState(
      key: key ?? this.key,
      isSubscribed: isSubscribed ?? this.isSubscribed,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LicenseState &&
        other.key == key &&
        other.isSubscribed == isSubscribed;
  }

  @override
  int get hashCode => Object.hash(key, isSubscribed);

  @override
  String toString() =>
      'LicenseState(isSubscribed: $isSubscribed, hasKey: ${key != null})';
}
