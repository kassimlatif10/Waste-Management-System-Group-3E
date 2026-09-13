import 'package:wastmobile/services/app_config.dart';

class ApiConstants {
  ApiConstants._();

  static String get baseUrl => '${AppConfig.baseUrl}/api';
  static String get wsBase => AppConfig.wsUrl;

  // ── OpenRouteService (ORS) ───────────────────────────────────────────────────
  // Free key at https://openrouteservice.org/dev/#/signup
  // Leave empty to use OSRM public server (no key needed, road-following routes)
  static const String orsApiKey = '';

  // ── WebSocket tracking ──────────────────────────────────────────────────────
  static String wsTracking(int requestId) => '$wsBase/tracking/$requestId/';

  // ── Auth ────────────────────────────────────────────────────────────────────
  static String get checkPhone => '$baseUrl/auth/check-phone/';
  static String get phoneLogin => '$baseUrl/auth/phone-login/';
  static String get setPassword => '$baseUrl/auth/set-password/';
  static String get changePassword => '$baseUrl/auth/change-password/';
  static String get sendOtp => '$baseUrl/auth/send-otp/';
  static String get verifyOtp => '$baseUrl/auth/verify-otp/';
  static String get registerCustomer => '$baseUrl/auth/register/customer/';
  static String get registerCollector => '$baseUrl/auth/register/collector/';
  static String get adminLogin => '$baseUrl/auth/admin/login/';
  static String get devLogin => '$baseUrl/auth/dev-login/';
  static String get tokenRefresh => '$baseUrl/auth/token/refresh/';
  static String get logout => '$baseUrl/auth/logout/';
  static String get me => '$baseUrl/auth/me/';
  static String get registerDevice => '$baseUrl/auth/register-device/';

  // ── Customer — static ───────────────────────────────────────────────────────
  static String get wasteTypes => '$baseUrl/customer/waste-types/';
  static String get customerProfile => '$baseUrl/customer/profile/';
  static String get customerRequests => '$baseUrl/customer/requests/';
  static String get customerActiveRequest =>
      '$baseUrl/customer/requests/active/';
  static String get customerNotifications => '$baseUrl/customer/notifications/';
  static String get customerMarkAllRead =>
      '$baseUrl/customer/notifications/mark-all-read/';
  static String get customerSupport => '$baseUrl/customer/support/';
  static String customerSupportTicket(int id) => '$baseUrl/customer/support/$id/';
  static String get customerSchedules => '$baseUrl/customer/schedules/';
  static String get customerAddresses => '$baseUrl/customer/addresses/';
  static String get customerReports => '$baseUrl/customer/reports/';

  // ── Collector — static ──────────────────────────────────────────────────────
  static String get collectorProfile => '$baseUrl/collector/profile/';
  static String get collectorToggleOnline =>
      '$baseUrl/collector/toggle-online/';
  static String get collectorLocation => '$baseUrl/collector/location/';
  static String get collectorPendingRequests =>
      '$baseUrl/collector/pending-requests/';
  static String get collectorIncoming =>
      '$baseUrl/collector/incoming-requests/';
  static String get collectorActiveRequest =>
      '$baseUrl/collector/active-request/';
  static String get collectorCollections => '$baseUrl/collector/collections/';
  static String get collectorSchedules => '$baseUrl/collector/schedules/';
  static String get collectorNotifications =>
      '$baseUrl/collector/notifications/';
  static String get collectorCreditScore => '$baseUrl/collector/credit-score/';
  static String get collectorSupport => '$baseUrl/collector/support/';
  static String get collectorRegisterVehicle => '$baseUrl/collector/vehicles/register/';
  static String get collectorMarkAllNotificationsRead => '$baseUrl/collector/notifications/';

  // ── Admin — static ──────────────────────────────────────────────────────────
  static String get adminDashboard => '$baseUrl/admin/dashboard/';
  static String get adminCustomers => '$baseUrl/admin/customers/';
  static String get adminCollectors => '$baseUrl/admin/collectors/';
  static String get adminCollections => '$baseUrl/admin/collections/';
  static String get adminSchedules => '$baseUrl/admin/schedules/';
  static String adminSchedule(int id) => '$baseUrl/admin/schedules/$id/';
  static String get adminReports => '$baseUrl/admin/reports/';
  static String get adminTickets => '$baseUrl/admin/tickets/';
  static String adminTicket(int id) => '$baseUrl/admin/tickets/$id/';
  static String adminTicketResolve(int id) => '$baseUrl/admin/tickets/$id/resolve/';
  static String get adminInvestors => '$baseUrl/admin/investors/';
  static String get adminProfile => '$baseUrl/admin/profile/';
  static String get adminSystemConfig => '$baseUrl/admin/system-config/';
  static String get adminCompanyBins => '$baseUrl/admin/company-bins/';
  static String adminCompanyBin(int id) => '$baseUrl/admin/company-bins/$id/';
  static String get adminVehicles => '$baseUrl/admin/vehicles/';
  static String adminVehicle(int id) => '$baseUrl/admin/vehicles/$id/';
  static String get adminWasteTypes => '$baseUrl/admin/waste-types/';
  static String adminWasteType(int id) => '$baseUrl/admin/waste-types/$id/';
  static String get adminBinTypes => '$baseUrl/admin/bin-types/';
  static String adminBinType(int id) => '$baseUrl/admin/bin-types/$id/';
  static String get customerProfileUpdate => '$baseUrl/customer/profile/update/';
  static String get collectorKyc => '$baseUrl/collector/kyc/';

  // ── Investor ────────────────────────────────────────────────────────────────
  static String get investorDashboard => '$baseUrl/investor/dashboard/';
  static String get investorProfile => '$baseUrl/investor/profile/';
  static String get investorEarnings => '$baseUrl/investor/earnings/';
  static String get investorRides => '$baseUrl/investor/rides/';
  static String get investorCollectors => '$baseUrl/investor/collectors/';
  static String investorRide(int id) => '$baseUrl/investor/rides/$id/';

  // ── Collector — Vehicles ─────────────────────────────────────────────────
  static String get collectorVehicles => '$baseUrl/collector/vehicles/';

  // ── Dynamic paths ────────────────────────────────────────────────────────────
  static String customerRequest(int id) => '$baseUrl/customer/requests/$id/';
  static String cancelRequest(int id) =>
      '$baseUrl/customer/requests/$id/cancel/';
  static String rateRequest(int id) => '$baseUrl/customer/requests/$id/rate/';
  static String acceptCollector(int id) =>
      '$baseUrl/customer/requests/$id/accept-collector/';
  static String skipCollector(int id) =>
      '$baseUrl/customer/requests/$id/skip-collector/';
  static String cancelSchedule(int id) => '$baseUrl/customer/schedules/$id/';
  static String deleteAddress(int id) => '$baseUrl/customer/addresses/$id/';

  static String acceptRequest(int id) =>
      '$baseUrl/collector/requests/$id/accept/';
  static String declineRequest(int id) =>
      '$baseUrl/collector/requests/$id/decline/';
  static String markOnWay(int id) => '$baseUrl/collector/requests/$id/on-way/';
  static String markArrived(int id) =>
      '$baseUrl/collector/requests/$id/arrived/';
  static String completePickup(int id) =>
      '$baseUrl/collector/requests/$id/complete/';
  static String confirmSchedule(int id) =>
      '$baseUrl/collector/schedules/$id/confirm/';
  static String collectorCollection(int id) =>
      '$baseUrl/collector/collections/$id/';
  static String collectorNotificationRead(int id) =>
      '$baseUrl/collector/notifications/$id/read/';
  static String collectorSupportTicket(int id) => '$baseUrl/collector/support/$id/';
  static String collectorVehicleDetail(int id) => '$baseUrl/collector/vehicles/$id/detail/';

  static String adminInvestor(int id) => '$baseUrl/admin/investors/$id/';
  static String adminInvestorAddEarning(int id) => '$baseUrl/admin/investors/$id/earnings/';
  static String collectorVehicle(int id) => '$baseUrl/collector/vehicles/$id/';
  static String collectorVehicleSetDefault(int id) => '$baseUrl/collector/vehicles/$id/set-default/';
  static String collectorRequest(int id) => '$baseUrl/collector/requests/$id/';
  static String triggerSchedule(int id) => '$baseUrl/customer/schedules/$id/trigger/';
  static String approveCollector(int id) => '$baseUrl/admin/collectors/$id/approve/';
  static String declineCollector(int id) => '$baseUrl/admin/collectors/$id/decline/';
  static String suspendCollector(int id) => '$baseUrl/admin/collectors/$id/suspend/';
  static String collectorKycDetail(int id) => '$baseUrl/admin/collectors/$id/kyc/';
  static String adjustCollectorScore(int id) => '$baseUrl/admin/collectors/$id/score/';
  static String assignCollection(int id) => '$baseUrl/admin/collections/$id/assign/';
  static String assignSchedule(int id) => '$baseUrl/admin/schedules/$id/assign/';
  static String resolveReport(int id) => '$baseUrl/admin/reports/$id/resolve/';

  // ── Password reset (OTP-based) ───────────────────────────────────────────
  static String get forgotPassword => '$baseUrl/auth/forgot-password/';
  static String get resetPassword => '$baseUrl/auth/reset-password/';

  // ── Public ────────────────────────────────────────────────────────────────
  static String get publicBranches => '$baseUrl/public/branches/';

  // ── Super-Admin ───────────────────────────────────────────────────────────
  static String get superAdminBranches => '$baseUrl/super-admin/branches/';
  static String get superAdminBranchesBulkRadius => '$baseUrl/super-admin/branches/bulk-radius/';
  static String superAdminBranch(int id) => '$baseUrl/super-admin/branches/$id/';
  static String get superAdminAdmins => '$baseUrl/super-admin/admins/';
  static String superAdminAdmin(int id) => '$baseUrl/super-admin/admins/$id/';
  static String superAdminDeleteAdmin(int id) => '$baseUrl/super-admin/admins/$id/';
  static String superAdminDeleteCustomer(int id) => '$baseUrl/super-admin/customers/$id/delete/';
  static String superAdminDeleteCollector(int id) => '$baseUrl/super-admin/collectors/$id/delete/';
  static String superAdminDeleteInvestor(int id) => '$baseUrl/super-admin/investors/$id/delete/';

  // ── Geocoding (server-side Google Places / Geocoding) ─────────────────────
  static String geoReverse(double lat, double lng) =>
      '$baseUrl/geo/reverse/?lat=$lat&lng=$lng';
  static String geoSearch(String query) =>
      '$baseUrl/geo/search/?q=${Uri.encodeComponent(query)}';
}
