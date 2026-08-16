import 'package:flutter/material.dart';

import '../../controllers/address_search_controller.dart';
import '../../data/address_search_repository.dart';

class AddressSearchField extends StatefulWidget {
  const AddressSearchField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.enabled = true,
  });
  final AddressSearchController controller;
  final ValueChanged<ResolvedAddress> onSelected;
  final bool enabled;

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_focused);
  }

  void _focused() {
    if (_focus.hasFocus) widget.controller.focus();
  }

  void _changed() {
    if (!mounted) return;
    final selected = widget.controller.selectedAddress;
    if (selected != null && _text.text != widget.controller.query) {
      _syncing = true;
      _text.value = TextEditingValue(
        text: widget.controller.query,
        selection: TextSelection.collapsed(
          offset: widget.controller.query.length,
        ),
      );
      _syncing = false;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant AddressSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_focused);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('address-search-field'),
          controller: _text,
          focusNode: _focus,
          enabled: widget.enabled,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Adres ara',
            hintText: 'En az 3 karakter yazın',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _text.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Adres aramasını temizle',
                    onPressed: () {
                      _text.clear();
                      widget.controller.queryChanged('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onChanged: (value) {
            if (!_syncing) widget.controller.queryChanged(value);
          },
        ),
        if (state == AddressSearchStatus.loading)
          const Padding(
            key: Key('address-loading'),
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (state == AddressSearchStatus.results)
          AddressSuggestionList(
            suggestions: widget.controller.suggestions,
            onSelected: _select,
          ),
        if (state == AddressSearchStatus.empty)
          const _Message(
            key: Key('address-empty'),
            icon: Icons.search_off,
            text: 'Bu aramayla eşleşen Türkiye adresi bulunamadı.',
          ),
        if (state == AddressSearchStatus.rateLimited)
          _Message(
            key: const Key('address-rate-limit'),
            icon: Icons.schedule,
            text: 'Çok sık arama yapıldı. Biraz bekleyip tekrar deneyin.',
            retry: widget.controller.retry,
          ),
        if (state == AddressSearchStatus.providerUnavailable)
          _Message(
            key: const Key('address-provider-unavailable'),
            icon: Icons.cloud_off,
            text: 'Adres hizmeti şu anda kullanılamıyor.',
            retry: widget.controller.retry,
          ),
        if (state == AddressSearchStatus.networkError)
          _Message(
            key: const Key('address-network-error'),
            icon: Icons.wifi_off,
            text: 'Adresler alınamadı. Bağlantınızı kontrol edin.',
            retry: widget.controller.retry,
          ),
        if (state == AddressSearchStatus.incomplete)
          const _Message(
            key: Key('address-incomplete'),
            icon: Icons.edit_location_alt,
            text:
                'Adresin bazı bölümleri eksik. Aşağıdaki alanları elle tamamlayabilirsiniz.',
          ),
        if (state == AddressSearchStatus.selected)
          const _Message(
            key: Key('address-selected'),
            icon: Icons.check_circle_outline,
            text: 'Adres seçildi. Alanları ve harita konumunu kontrol edin.',
          ),
      ],
    );
  }

  Future<void> _select(AddressSuggestion suggestion) async {
    final result = await widget.controller.select(suggestion);
    if (result != null && mounted) {
      widget.onSelected(result);
      _focus.unfocus();
    }
  }
}

class AddressSuggestionList extends StatelessWidget {
  const AddressSuggestionList({
    super.key,
    required this.suggestions,
    required this.onSelected,
  });
  final List<AddressSuggestion> suggestions;
  final ValueChanged<AddressSuggestion> onSelected;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 240),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: ListView.separated(
        key: const Key('address-suggestions'),
        shrinkWrap: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = suggestions[index];
          return ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(item.primaryText, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              item.secondaryText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelected(item),
          );
        },
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.text,
    this.retry,
  });
  final IconData icon;
  final String text;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Tekrar dene')),
      ],
    ),
  );
}
