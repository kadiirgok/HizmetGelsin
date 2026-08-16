const TestCustomer testCustomer = (
  id: '10000000-0000-4000-8000-000000000001',
  displayName: 'E2E Test Müşteri',
);
const TestBusiness testBusiness = (
  id: '20000000-0000-4000-8000-000000000001',
  name: 'E2E Test İşletme',
);
const TestService testService = (
  id: '30000000-0000-4000-8000-000000000001',
  name: 'E2E Test Hizmet',
);
const TestAddress testAddress = (
  id: '40000000-0000-4000-8000-000000000001',
  label: 'E2E Test Adresi',
);
const TestRequest testRequest = (
  id: '50000000-0000-4000-8000-000000000001',
  status: 'Pending',
);
const TestOffer testOffer = (
  id: '60000000-0000-4000-8000-000000000001',
  status: 'Pending',
);
const TestAppointment testAppointment = (
  id: '70000000-0000-4000-8000-000000000001',
  status: 'Accepted',
);
const TestRating testRating = (
  id: '80000000-0000-4000-8000-000000000001',
  score: 5,
);
const TestNotification testNotification = (
  id: '90000000-0000-4000-8000-000000000001',
  route: '/talep/50000000-0000-4000-8000-000000000001',
);

typedef TestCustomer = ({String id, String displayName});
typedef TestBusiness = ({String id, String name});
typedef TestService = ({String id, String name});
typedef TestAddress = ({String id, String label});
typedef TestRequest = ({String id, String status});
typedef TestOffer = ({String id, String status});
typedef TestAppointment = ({String id, String status});
typedef TestRating = ({String id, int score});
typedef TestNotification = ({String id, String route});
