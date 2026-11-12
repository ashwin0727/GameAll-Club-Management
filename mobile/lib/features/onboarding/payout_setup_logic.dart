import 'dart:convert';

import 'package:http/http.dart' as http;

/// Banks offered in the payout form's dropdown (same list as the web `src/features/payout-setup/banks.ts`).
const List<String> indianBanks = [
  'State Bank of India',
  'HDFC Bank',
  'ICICI Bank',
  'Axis Bank',
  'Kotak Mahindra Bank',
  'Punjab National Bank',
  'Bank of Baroda',
  'Canara Bank',
  'Union Bank of India',
  'Bank of India',
  'Indian Bank',
  'Central Bank of India',
  'Indian Overseas Bank',
  'UCO Bank',
  'Bank of Maharashtra',
  'Punjab & Sind Bank',
  'IDFC FIRST Bank',
  'IndusInd Bank',
  'Yes Bank',
  'Federal Bank',
  'South Indian Bank',
  'Karnataka Bank',
  'Karur Vysya Bank',
  'City Union Bank',
  'RBL Bank',
  'Bandhan Bank',
  'IDBI Bank',
  'AU Small Finance Bank',
  'Equitas Small Finance Bank',
  'Ujjivan Small Finance Bank',
  'Jammu & Kashmir Bank',
  'DCB Bank',
  'Tamilnad Mercantile Bank',
  'Saraswat Co-operative Bank',
  'Paytm Payments Bank',
  'Airtel Payments Bank',
  'India Post Payments Bank',
  'Standard Chartered Bank',
  'HSBC',
  'Citibank',
  'Deutsche Bank',
];

const Map<String, String> _ifscPrefix = {
  'SBIN': 'State Bank of India',
  'HDFC': 'HDFC Bank',
  'ICIC': 'ICICI Bank',
  'UTIB': 'Axis Bank',
  'KKBK': 'Kotak Mahindra Bank',
  'PUNB': 'Punjab National Bank',
  'BARB': 'Bank of Baroda',
  'CNRB': 'Canara Bank',
  'UBIN': 'Union Bank of India',
  'BKID': 'Bank of India',
  'IDIB': 'Indian Bank',
  'CBIN': 'Central Bank of India',
  'IOBA': 'Indian Overseas Bank',
  'UCBA': 'UCO Bank',
  'MAHB': 'Bank of Maharashtra',
  'PSIB': 'Punjab & Sind Bank',
  'IDFB': 'IDFC FIRST Bank',
  'INDB': 'IndusInd Bank',
  'YESB': 'Yes Bank',
  'FDRL': 'Federal Bank',
  'SIBL': 'South Indian Bank',
  'KARB': 'Karnataka Bank',
  'KVBL': 'Karur Vysya Bank',
  'CIUB': 'City Union Bank',
  'RATN': 'RBL Bank',
  'BDBL': 'Bandhan Bank',
  'IBKL': 'IDBI Bank',
  'AUBL': 'AU Small Finance Bank',
  'ESFB': 'Equitas Small Finance Bank',
  'USFB': 'Ujjivan Small Finance Bank',
  'JAKA': 'Jammu & Kashmir Bank',
  'DCBL': 'DCB Bank',
  'TMBL': 'Tamilnad Mercantile Bank',
  'PYTM': 'Paytm Payments Bank',
  'AIRP': 'Airtel Payments Bank',
  'IPOS': 'India Post Payments Bank',
  'SCBL': 'Standard Chartered Bank',
  'HSBC': 'HSBC',
  'CITI': 'Citibank',
  'DEUT': 'Deutsche Bank',
};

/// The bank an IFSC belongs to, from its first four letters, when we know it.
String? bankFromIfsc(String ifsc) {
  final t = ifsc.trim().toUpperCase();
  return t.length < 4 ? null : _ifscPrefix[t.substring(0, 4)];
}

class IfscDetails {
  const IfscDetails({required this.bank, required this.branch, required this.city});
  final String bank;
  final String branch;
  final String city;
}

/// Looks an IFSC up in the public directory (ifsc.razorpay.com). Null when the code does not exist; throws when the directory cannot
/// be reached, so the caller can say "try again" instead of "not found".
Future<IfscDetails?> lookupIfsc(String code, {http.Client? client}) async {
  final ifsc = code.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)) return null;
  final c = client ?? http.Client();
  try {
    final res = await c.get(Uri.https('ifsc.razorpay.com', '/$ifsc'), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('IFSC directory unavailable');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final bank = j['BANK'] as String?;
    if (bank == null) return null;
    return IfscDetails(bank: bankFromIfsc(ifsc) ?? bank, branch: j['BRANCH'] as String? ?? '', city: j['CITY'] as String? ?? '');
  } finally {
    if (client == null) c.close();
  }
}
