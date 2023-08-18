bool mapEquals(Map<dynamic, dynamic>? map1, Map<dynamic, dynamic>? map2) {
  if (identical(map1, map2)) return true;
  if (map1 == null || map2 == null) return false;
  if (map1.length != map2.length) return false;

  for (final key in map1.keys) {
    if (!map2.containsKey(key)) return false;
    final value1 = map1[key];
    final value2 = map2[key];
    if (value1 is Map && value2 is Map) {
      if (!mapEquals(value1, value2)) return false;
    } else if (value1 != value2) {
      return false;
    }
  }

  return true;
}