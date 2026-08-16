import 'package:berbergelsin/features/addresses/data/client_addresses_repo.dart';
import 'package:berbergelsin/features/addresses/widgets/customer_address_semantics.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

ClientAddress _address({
  required String id,
  required String label,
  required bool isDefault,
}) => ClientAddress(
  id: id,
  label: label,
  addressLine: 'Uzun açık adres, bina 12, daire 4',
  province: 'İstanbul',
  district: 'Beşiktaş',
  latitude: 41.01,
  longitude: 29.02,
  isDefault: isDefault,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  version: 'secret-version',
);

void main() {
  testWidgets(
    'saved address exposes short, default and selected radio-like semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final home = _address(id: 'address-1', label: 'Ev', isDefault: true);
      final work = _address(id: 'address-2', label: 'İş', isDefault: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CustomerAddressSemantics(
                  address: home,
                  selected: true,
                  onTap: () {},
                  child: const ListTile(title: Text('Ev')),
                ),
                CustomerAddressSemantics(
                  address: work,
                  selected: false,
                  onTap: () {},
                  child: const ListTile(title: Text('İş')),
                ),
              ],
            ),
          ),
        ),
      );

      final selected = find.bySemanticsLabel(
        'Ev, Beşiktaş İstanbul, varsayılan adres, seçili',
      );
      final unselected = find.bySemanticsLabel(
        'İş, Beşiktaş İstanbul, varsayılan değil, seçili değil',
      );
      expect(selected, findsOneWidget);
      expect(unselected, findsOneWidget);
      expect(
        tester.getSemantics(selected).flagsCollection.isButton,
        isTrue,
      );
      expect(
        tester.getSemantics(selected).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(unselected).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      final label = tester.getSemantics(selected).label;
      expect(label, isNot(contains('address-1')));
      expect(label, isNot(contains('41.01')));
      expect(label, isNot(contains('Uzun açık adres')));
      semantics.dispose();
    },
  );

  testWidgets('manual address exposes selection and button semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerManualAddressSemantics(
            selected: false,
            onTap: () {},
            child: const ListTile(title: Text('Manuel adres gir')),
          ),
        ),
      ),
    );
    final manual = find.bySemanticsLabel('Manuel adres gir, seçili değil');
    expect(manual, findsOneWidget);
    expect(tester.getSemantics(manual).flagsCollection.isButton, isTrue);
    expect(
      tester.getSemantics(manual).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    semantics.dispose();
  });
}
