import 'package:flutter/material.dart';

import '../data/client_addresses_repo.dart';

String customerAddressShortDescription(ClientAddress address) {
  final locality = [address.district, address.province]
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ');
  if (locality.isNotEmpty) return locality;
  final fallback = address.addressLine.replaceAll(RegExp(r'\s+'), ' ').trim();
  return fallback.length <= 64 ? fallback : '${fallback.substring(0, 61)}…';
}

String customerAddressSemanticsLabel(
  ClientAddress address, {
  required bool selected,
}) =>
    '${address.label}, ${customerAddressShortDescription(address)}, '
    '${address.isDefault ? 'varsayılan adres' : 'varsayılan değil'}, '
    '${selected ? 'seçili' : 'seçili değil'}';

class CustomerAddressSemantics extends StatelessWidget {
  const CustomerAddressSemantics({
    super.key,
    required this.address,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final ClientAddress address;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: customerAddressSemanticsLabel(address, selected: selected),
    onTap: onTap,
    child: ExcludeSemantics(child: child),
  );
}

class CustomerManualAddressSemantics extends StatelessWidget {
  const CustomerManualAddressSemantics({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: 'Manuel adres gir, ${selected ? 'seçili' : 'seçili değil'}',
    onTap: onTap,
    child: ExcludeSemantics(child: child),
  );
}
