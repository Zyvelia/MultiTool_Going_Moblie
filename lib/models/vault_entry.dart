class VaultEntry {
  final String id;
  final String site;
  final String username;
  final String password;
  final String category;
  final bool favorite;

  VaultEntry({
    required this.id,
    required this.site,
    required this.username,
    required this.password,
    required this.category,
    required this.favorite,
  });

  factory VaultEntry.fromJson(Map<String, dynamic> json) {
    return VaultEntry(
      id: json['id']?.toString() ?? '',
      site: json['site'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      category: json['category'] as String? ?? '',
      favorite: json['favorite'] as bool? ?? false,
    );
  }
}

class TotpCode {
  final String id;
  final String name;
  final String issuer;
  final String code;

  TotpCode({
    required this.id,
    required this.name,
    required this.issuer,
    required this.code,
  });

  factory TotpCode.fromJson(Map<String, dynamic> json) {
    return TotpCode(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      issuer: json['issuer'] as String? ?? '',
      code: json['code'] as String? ?? '',
    );
  }
}
