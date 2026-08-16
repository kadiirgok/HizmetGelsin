import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_cubit.dart';
import '../controllers/notification_store.dart';

class NotificationButton extends StatefulWidget {
  const NotificationButton({super.key});
  @override
  State<NotificationButton> createState() => _S();
}

class _S extends State<NotificationButton> {
  final store = NotificationStore.instance;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.read<AuthCubit>().state.user?.id;
    if (id != null) store.bindSession(id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => IconButton(
      tooltip: 'Bildirimler',
      onPressed: () => context.push('/bildirimler'),
      icon: Badge(
        isLabelVisible: store.unread > 0,
        label: Text(store.unread > 99 ? '99+' : '${store.unread}'),
        child: const Icon(Icons.notifications_outlined),
      ),
    ),
  );
}
