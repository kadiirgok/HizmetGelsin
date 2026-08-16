import 'package:flutter/material.dart';

import 'customer_smoke/customer_smoke_app.dart';
import 'customer_smoke/customer_smoke_repository.dart';

const bool _customerSmokeMode = bool.fromEnvironment(
  'CUSTOMER_SMOKE_MODE',
  defaultValue: false,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!_customerSmokeMode) {
    throw StateError(
      'Customer smoke entrypoint requires CUSTOMER_SMOKE_MODE=true.',
    );
  }
  runApp(CustomerSmokeApp(dependencies: CustomerSmokeDependencies.isolated()));
}
