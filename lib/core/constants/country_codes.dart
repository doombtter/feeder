/// 전화번호 국가 코드(+XX) → 국가명 매핑
///
/// FirebaseAuth의 phoneNumber(예: "+821012345678")에서 앞자리를 파싱해
/// 국가명을 반환합니다.
class CountryCodes {
  /// 자주 쓰이는 국가들 우선. 필요시 확장.
  /// 긴 코드(+8XX)가 짧은 코드(+8)보다 먼저 매칭되도록 _lookup에서 길이 내림차순 정렬.
  static const Map<String, String> _codeToCountry = {
    '+82': '대한민국',
    '+1': '미국',          // 미국/캐나다 공통 — 구분은 번호만으로 불가
    '+81': '일본',
    '+86': '중국',
    '+852': '홍콩',
    '+853': '마카오',
    '+886': '대만',
    '+84': '베트남',
    '+66': '태국',
    '+63': '필리핀',
    '+62': '인도네시아',
    '+60': '말레이시아',
    '+65': '싱가포르',
    '+91': '인도',
    '+44': '영국',
    '+33': '프랑스',
    '+49': '독일',
    '+34': '스페인',
    '+39': '이탈리아',
    '+31': '네덜란드',
    '+351': '포르투갈',
    '+41': '스위스',
    '+46': '스웨덴',
    '+47': '노르웨이',
    '+45': '덴마크',
    '+358': '핀란드',
    '+7': '러시아',
    '+380': '우크라이나',
    '+48': '폴란드',
    '+61': '호주',
    '+64': '뉴질랜드',
    '+55': '브라질',
    '+52': '멕시코',
    '+54': '아르헨티나',
    '+56': '칠레',
    '+57': '콜롬비아',
    '+90': '튀르키예',
    '+971': '아랍에미리트',
    '+966': '사우디아라비아',
    '+972': '이스라엘',
    '+20': '이집트',
    '+27': '남아프리카공화국',
    '+234': '나이지리아',
  };

  /// 전체 전화번호("+821012345678")에서 국가명 반환.
  /// 매칭 실패 시 '기타' 반환.
  static String fromPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) return '';
    if (!phoneNumber.startsWith('+')) return '';

    // 긴 코드부터 매칭 (예: +852 가 +8 보다 먼저)
    final sortedCodes = _codeToCountry.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final code in sortedCodes) {
      if (phoneNumber.startsWith(code)) {
        return _codeToCountry[code]!;
      }
    }
    return '기타';
  }

  /// 전화번호가 한국 번호인지 여부.
  static bool isKorean(String? phoneNumber) {
    return (phoneNumber ?? '').startsWith('+82');
  }
}
