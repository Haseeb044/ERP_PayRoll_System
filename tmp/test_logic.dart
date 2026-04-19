
String _cleanHeader(String value) => value.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');

int _findColumnIndex(
    List<String> headers,
    List<String> keywords,
  ) {
    List<int> matches = [];
    for (var kw in keywords) {
        final target = _cleanHeader(kw);
        for (int i = 0; i < headers.length; i++) {
            final h = _cleanHeader(headers[i]);
            if (h.contains(target)) {
                matches.add(i);
            }
        }
        if (matches.isNotEmpty) break;
    }
    if (matches.isEmpty) return -1;
    return matches.first;
}

void main() {
  // Test 1: Underscore and Space matching
  var headers = ["PLATE_NUMBER", "FINE_AMOUNT", "TICKET_NO"];
  var plateKeywords = ["plate number", "plate no", "plate"];
  
  var idx = _findColumnIndex(headers, plateKeywords);
  print("Test 1 (PLATE_NUMBER vs plate number): Index $idx (Expected 0)");
  assert(idx == 0);

  // Test 2: Plate Normalization
  String rawPlate = "K 12345";
  String normalized = rawPlate.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  print("Test 2 (K 12345 normalization): $normalized (Expected K12345)");
  assert(normalized == "K12345");

  String rawPlate2 = "DXB-D-999";
  String normalized2 = rawPlate2.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  print("Test 3 (DXB-D-999 normalization): $normalized2 (Expected DXBD999)");
  assert(normalized2 == "DXBD999");

  print("All logic tests passed!");
}
