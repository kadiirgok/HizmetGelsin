import '../../features/addresses/data/client_addresses_repo.dart';
import '../../features/favorites/data/favorites_repo.dart';
import '../../features/notifications/controllers/notification_store.dart';
import 'customer_session_events.dart';

class AccountStateCleaner {
  const AccountStateCleaner._();

  static void clear() {
    NotificationStore.instance.clearSession();
    FavoriteStore.instance.clearSession();
    CustomerAddressSelectionStore.instance.clearSession();
  }

  static void bindCustomerSession(String? sessionKey) {
    if (CustomerSessionScope.instance.bind(sessionKey)) clear();
  }

  static void endCustomerSession() {
    CustomerSessionScope.instance.clear();
    clear();
  }
}
