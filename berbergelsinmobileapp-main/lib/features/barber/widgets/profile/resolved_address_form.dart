import 'package:flutter/material.dart';

class AddressLineForm extends StatelessWidget {
  const AddressLineForm({
    super.key,
    required this.addressLine,
    this.enabled = true,
  });
  final TextEditingController addressLine;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
    controller: addressLine,
    enabled: enabled,
    textCapitalization: TextCapitalization.sentences,
    minLines: 2,
    maxLines: 4,
    decoration: const InputDecoration(
      labelText: 'Açık Adres',
      hintText: 'Cadde, sokak, bina, daire veya buluşma noktası',
    ),
  );
}
