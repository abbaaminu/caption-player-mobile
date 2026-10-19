class LicenseState {
  final String? key;
  final bool isSubscribed;

  LicenseState({this.key, this.isSubscribed = false});

  factory LicenseState.fromJson(Map<String, dynamic> json) {
    return LicenseState(
      key: json['key'] as String?,
      isSubscribed: json['subscribed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'subscribed': isSubscribed,
    };
  }
}