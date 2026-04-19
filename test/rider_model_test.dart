import 'package:flutter_test/flutter_test.dart';
import 'package:rider_payroll_erp/data/models/rider_model.dart';

void main() {
  group('RiderModel serialization', () {
    test('fromJson reads new rider enhancement fields', () {
      final json = <String, dynamic>{
        'id': 'r1',
        'name': 'Test Rider',
        'status': 'active',
        'emirates_id_number': '784123',
        'passport_number': 'P123',
        'passport_expiry_date': '2028-01-01',
        'emirates_id_expiry_date': '2027-01-01',
        'visa_expiry_date': '2026-11-01',
        'hold_reason': 'Compliance check',
        'hold_until': '2026-04-30',
        'hold_set_by': 'u1',
        'hold_set_at': '2026-04-02T10:00:00Z',
      };

      final rider = RiderModel.fromJson(json);

      expect(rider.passportExpiryDate, '2028-01-01');
      expect(rider.emiratesIdExpiryDate, '2027-01-01');
      expect(rider.visaExpiryDate, '2026-11-01');
      expect(rider.holdReason, 'Compliance check');
      expect(rider.holdUntil, '2026-04-30');
      expect(rider.holdSetBy, 'u1');
      expect(rider.holdSetAt?.toUtc().toIso8601String(), '2026-04-02T10:00:00.000Z');
    });

    test('toJson writes new rider enhancement fields', () {
      final rider = RiderModel(
        id: 'r2',
        name: 'Another Rider',
        status: RiderStatus.vacation,
        passportExpiryDate: '2028-06-15',
        emiratesIdExpiryDate: '2027-06-15',
        visaExpiryDate: '2027-01-01',
        holdReason: 'Temporary hold',
        holdUntil: '2026-06-01',
      );

      final json = rider.toJson();

      expect(json['passport_expiry_date'], '2028-06-15');
      expect(json['emirates_id_expiry_date'], '2027-06-15');
      expect(json['visa_expiry_date'], '2027-01-01');
      expect(json['hold_reason'], 'Temporary hold');
      expect(json['hold_until'], '2026-06-01');
      expect(json['status'], 'vacation');
    });
  });
}
