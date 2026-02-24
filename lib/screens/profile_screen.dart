// File: lib/screens/profile_screen.dart (Teljes kód a javításokkal)

// ignore_for_file: unnecessary_cast, unused_local_variable

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// FIX: Removed unnecessary import - foundation.dart is already included via material.dart
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/profile_service.dart';
import '../services/gtc_service.dart';
import '../services/app_config_service.dart';
import '../widgets/responsive_layout.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _lastGtcSchoolId;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _familyNameController = TextEditingController();
  final _forenameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _address3Controller = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _gliderController = TextEditingController();
  final _shvNumberController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  String _selectedLicense = 'Student';
  String? _selectedSchoolId;
  String? _selectedNationality;
  String? _selectedCountry;
  DateTime? _birthday;
  double _height = 170.0;
  double _weight = 65.0;
  bool _formInitialized = false;
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  String? _lastProfileUid;
  ValueNotifier<int>? _syncNotifier;
  VoidCallback? _syncListener;
  int _lastSeenSyncTick = 0;
  bool _suppressAutoSave = false;
  

  // Top countries for quick access
  static const List<String> _topCountries = [
    'Austria', 'China', 'Germany', 'Hungary', 'India', 'Poland', 'Switzerland', 'United States of America'
  ];

  // Rest of world countries (includes all countries, top countries will be shown at top)
  static const List<String> _allCountries = [
    'Afghanistan', 'Albania', 'Algeria', 'Andorra', 'Angola', 'Antigua and Barbuda', 'Argentina', 'Armenia',
    'Australia', 'Austria', 'Azerbaijan', 'Bahamas', 'Bahrain', 'Bangladesh', 'Barbados', 'Belarus', 'Belgium',
    'Belize', 'Benin', 'Bhutan', 'Bolivia', 'Bosnia and Herzegovina', 'Botswana', 'Brazil', 'Brunei', 'Bulgaria',
    'Burkina Faso', 'Burundi', 'Cambodia', 'Cameroon', 'Canada', 'Cape Verde', 'Central African Republic', 'Chad',
    'Chile', 'China', 'Colombia', 'Comoros', 'Congo', 'Costa Rica', 'Croatia', 'Cuba', 'Cyprus', 'Czech Republic',
    'Denmark', 'Djibouti', 'Dominica', 'Dominican Republic', 'East Timor', 'Ecuador', 'Egypt', 'El Salvador',
    'Equatorial Guinea', 'Eritrea', 'Estonia', 'Ethiopia', 'Fiji', 'Finland', 'France', 'Gabon', 'Gambia', 'Georgia',
    'Germany', 'Ghana', 'Greece', 'Grenada', 'Guatemala', 'Guinea', 'Guinea-Bissau', 'Guyana', 'Haiti', 'Honduras',
    'Hungary', 'Iceland', 'India', 'Indonesia', 'Iran', 'Iraq', 'Ireland', 'Israel', 'Italy', 'Ivory Coast', 'Jamaica',
    'Japan', 'Jordan', 'Kazakhstan', 'Kenya', 'Kiribati', 'North Korea', 'South Korea', 'Kuwait', 'Kyrgyzstan', 'Laos',
    'Latvia', 'Lebanon', 'Lesotho', 'Liberia', 'Libya', 'Liechtenstein', 'Lithuania', 'Luxembourg', 'Macedonia',
    'Madagascar', 'Malawi', 'Malaysia', 'Maldives', 'Mali', 'Malta', 'Marshall Islands', 'Mauritania', 'Mauritius',
    'Mexico', 'Micronesia', 'Moldova', 'Monaco', 'Mongolia', 'Montenegro', 'Morocco', 'Mozambique', 'Myanmar', 'Namibia',
    'Nauru', 'Nepal', 'Netherlands', 'New Zealand', 'Nicaragua', 'Niger', 'Nigeria', 'Norway', 'Oman', 'Pakistan',
    'Palau', 'Panama', 'Papua New Guinea', 'Paraguay', 'Peru', 'Philippines', 'Poland', 'Portugal', 'Qatar', 'Romania',
    'Russia', 'Rwanda', 'Saint Kitts and Nevis', 'Saint Lucia', 'Saint Vincent and the Grenadines', 'Samoa', 'San Marino',
    'Sao Tome and Principe', 'Saudi Arabia', 'Senegal', 'Serbia', 'Seychelles', 'Sierra Leone', 'Singapore', 'Slovakia',
    'Slovenia', 'Solomon Islands', 'Somalia', 'South Africa', 'South Sudan', 'Spain', 'Sri Lanka', 'Sudan', 'Suriname',
    'Swaziland', 'Sweden', 'Switzerland', 'Syria', 'Taiwan', 'Tajikistan', 'Tanzania', 'Thailand', 'Togo', 'Tonga',
    'Trinidad and Tobago', 'Tunisia', 'Turkey', 'Turkmenistan', 'Tuvalu', 'Uganda', 'Ukraine', 'United Arab Emirates',
    'United Kingdom', 'United States of America', 'Uruguay', 'Uzbekistan', 'Vanuatu', 'Vatican City', 'Venezuela', 'Vietnam',
    'Yemen', 'Zambia', 'Zimbabwe'
  ];

  // Localization map
  static const Map<String, Map<String, String>> _texts = {
    'Personal_Details': {'en': 'Personal Details', 'de': 'Persönliche Angaben', 'it': 'Dati personali', 'fr': 'Données personnelles'},
    'Address': {'en': 'Address', 'de': 'Adresse', 'it': 'Indirizzo', 'fr': 'Adresse'},
    'Emergency_Contact': {'en': 'Emergency Contact', 'de': 'Notfallkontakt', 'it': 'Contatto di emergenza', 'fr': 'Contact d\'urgence'},
    'License_Equipment': {'en': 'License and Equipment', 'de': 'Lizenz und Ausrüstung', 'it': 'Licenza e attrezzatura', 'fr': 'Licence et équipement'},
    'Change_Password': {'en': 'Change Password', 'de': 'Passwort ändern', 'it': 'Cambia password', 'fr': 'Changer le mot de passe'},
    'Family_Name': {'en': 'Family Name', 'de': 'Familienname', 'it': 'Cognome', 'fr': 'Nom de famille'},
    'Forename': {'en': 'Forename', 'de': 'Vorname', 'it': 'Nome', 'fr': 'Prénom'},
    'Nickname': {'en': 'Nickname', 'de': 'Spitzname', 'it': 'Soprannome', 'fr': 'Surnom'},
    'Date_of_Birth': {'en': 'Date of Birth', 'de': 'Geburtsdatum', 'it': 'Data di nascita', 'fr': 'Date de naissance'},
    'Phone_Number': {'en': 'Phone Number', 'de': 'Telefonnummer', 'it': 'Numero di telefono', 'fr': 'Numéro de téléphone'},
    'Email_Address': {'en': 'Email Address', 'de': 'E-Mail-Adresse', 'it': 'Indirizzo e-mail', 'fr': 'Adresse e-mail'},
    'Nationality': {'en': 'Nationality', 'de': 'Nationalität', 'it': 'Nazionalità', 'fr': 'Nationalité'},
    'Street_Nr': {'en': 'Street & Nr', 'de': 'Straße & Nr.', 'it': 'Via e n.', 'fr': 'Rue et n°'},
    'ZIP': {'en': 'ZIP', 'de': 'PLZ', 'it': 'CAP', 'fr': 'Code postal'},
    'City': {'en': 'City', 'de': 'Stadt', 'it': 'Città', 'fr': 'Ville'},
    'Country': {'en': 'Country', 'de': 'Land', 'it': 'Paese', 'fr': 'Pays'},
    'Full_Name': {'en': 'Full Name', 'de': 'Voller Name', 'it': 'Nome completo', 'fr': 'Nom complet'},
    'Glider': {'en': 'Glider', 'de': 'Gleitschirm', 'it': 'Parapendio', 'fr': 'Parapente'},
    'SHV_Number': {'en': 'SHV Number', 'de': 'SHV Nummer', 'it': 'Numero SHV', 'fr': 'Numéro SHV'},
    'Old_Password': {'en': 'Old Password', 'de': 'Altes Passwort', 'it': 'Vecchia password', 'fr': 'Ancien mot de passe'},
    'New_Password': {'en': 'New Password', 'de': 'Neues Passwort', 'it': 'Nuova password', 'fr': 'Nouveau mot de passe'},
    'Required_Field': {'en': 'Required', 'de': 'Erforderlich', 'it': 'Obbligatorio', 'fr': 'Obligatoire'},
    'Save': {'en': 'Save', 'de': 'Speichern', 'it': 'Salva', 'fr': 'Enregistrer'},
    'Password_Success': {'en': 'Password changed!', 'de': 'Passwort geändert!', 'it': 'Password cambiata!', 'fr': 'Mot de passe changé !'},
    'Profile_Saved_Offline': {'en': 'Data saved to cache (Offline)', 'de': 'Daten im Cache gespeichert (Offline)', 'it': 'Dati salvati nella cache (Offline)', 'fr': 'Données enregistrées en cache (Hors ligne)'},
    'Profile_Saved_Online': {'en': 'Profile saved successfully', 'de': 'Profil erfolgreich gespeichert', 'it': 'Profilo salvato con successo', 'fr': 'Profil enregistré avec succès'},
    'Height': {'en': 'Height', 'de': 'Größe', 'it': 'Altezza', 'fr': 'Taille'},
    'Weight': {'en': 'Weight', 'de': 'Gewicht', 'it': 'Peso', 'fr': 'Poids'},
    'License': {'en': 'License', 'de': 'Lizenz', 'it': 'Licenza', 'fr': 'Licence'},
    'School': {'en': 'School', 'de': 'Schule', 'it': 'Scuola', 'fr': 'École'},
    'Student': {'en': 'Student', 'de': 'Schüler', 'it': 'Studente', 'fr': 'Élève'},
    'Pilot': {'en': 'Pilot', 'de': 'Pilot', 'it': 'Pilota', 'fr': 'Pilote'},
    'Select_School': {'en': 'Select school', 'de': 'Schule auswählen', 'it': 'Seleziona scuola', 'fr': 'Sélectionner l\'école'},
    'Synced_Cloud': {'en': 'Synced with cloud', 'de': 'Mit Cloud synchronisiert', 'it': 'Sincronizzato con il cloud', 'fr': 'Synchronisé avec le cloud'},
    'Password_Error': {'en': 'Error changing password', 'de': 'Fehler beim Ändern des Passworts', 'it': 'Errore nel cambio password', 'fr': 'Erreur lors du changement de mot de passe'},
    'Empty_Password_Fields': {'en': 'Both password fields are required', 'de': 'Beide Passwortfelder sind erforderlich', 'it': 'Entrambi i campi password sono obbligatori', 'fr': 'Les deux champs de mot de passe sont obligatoires'},
  };

  String _t(String key, String lang) {
    return _texts[key]?[lang] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _attachChangeListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setupSyncListener();
    });
  }

  @override
  void dispose() {
    _familyNameController.dispose();
    _forenameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _address3Controller.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _gliderController.dispose();
    _shvNumberController.dispose();
    _birthdayController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    if (_syncNotifier != null && _syncListener != null) {
      _syncNotifier!.removeListener(_syncListener!);
    }
    super.dispose();
  }

  void _attachChangeListeners() {
    for (final controller in [
      _familyNameController,
      _forenameController,
      _nicknameController,
      _phoneController,
      _address1Controller,
      _address2Controller,
      _address3Controller,
      _emergencyNameController,
      _emergencyPhoneController,
      _gliderController,
      _shvNumberController,
      _birthdayController,
    ]) {
      controller.addListener(_autoSaveProfile);
    }
  }

  // Controllerek és állapotaik nullázása
  void _clearControllers() {
    _familyNameController.clear();
    _forenameController.clear();
    _nicknameController.clear();
    _phoneController.clear();
    _address1Controller.clear();
    _address2Controller.clear();
    _address3Controller.clear();
    _emergencyNameController.clear();
    _emergencyPhoneController.clear();
    _gliderController.clear();
    _shvNumberController.clear();
    _birthdayController.clear();
    _oldPasswordController.clear();
    _newPasswordController.clear();
    setState(() {
      _selectedLicense = 'Student';
      _selectedSchoolId = null;
      _selectedNationality = null;
      _selectedCountry = null;
      _birthday = null;
      _height = 170.0;
      _weight = 65.0;
    });
  }

  // JAVÍTOTT: A didChangeDependencies logikája a stream frissítések kezelésére
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.watch<ProfileService>();
    final profile = service.userProfile;

    // GTC előtöltés: ha a user Student és van mainSchoolId, mindig töltsük le a GTC-t (could be removed for release)
    final gtcService = context.read<GTCService>();
    final schoolId = profile?.mainSchoolId;
    final isStudent = (profile?.license ?? '').toLowerCase() == 'student';
    if (isStudent && schoolId != null && schoolId != _lastGtcSchoolId) {
      debugPrint('[ProfileScreen] Preloading GTC for school: $schoolId');
      _lastGtcSchoolId = schoolId;
      gtcService.loadGTC(schoolId);
      gtcService.checkGTCAcceptance(profile!.uid!, schoolId);
    }

    // Ha a service töltődik és még nincs profil, kivárjuk. 
    // Itt NEM térünk vissza feltétel nélkül, hogy a build() le tudja kezelni a loading állapotot
    if (service.isLoading && profile == null) {
        return; 
    }
    
    if (profile != null) {
      final isNewUserOrUninitialized = !_formInitialized || _lastProfileUid != profile.uid;

      if (isNewUserOrUninitialized) {
          // 1. KEZDETI INICIALIZÁLÁS: Töltjük az ÖSSZES Controllert és State-et.
          _loadProfile(profile, forceSync: true); 
          _lastProfileUid = profile.uid;
          _formInitialized = true;
      } else {
          // 2. STREAM FRISSÍTÉS: Csak az eltérő értékeket frissítjük a streamről.
          _updateProfileFromStream(profile); 
      }
      
    } else if (profile == null && _formInitialized) {
      // Profil kiürítése (pl. logout)
      _formInitialized = false;
      _lastProfileUid = null;
      _clearControllers(); 
    }
  }


  // ÚJ METÓDUS: Csak a stream által küldött adatok frissítése, 
  // ha azok eltérnek a Controller aktuális tartalmától
  void _updateProfileFromStream(UserProfile profile) {
      _suppressAutoSave = true;

      // Frissítjük a State-hez kötött változókat (setState szükséges)
      setState(() {
          _selectedNationality = profile.nationality;
          _selectedCountry = profile.address4;
          _height = (profile.height != null && profile.height! > 0) ? profile.height!.toDouble() : 170.0;
          _weight = (profile.weight != null && profile.weight! > 0) ? profile.weight!.toDouble() : 65.0;
          
          final rawLicense = profile.license ?? 'Student';
          _selectedLicense = rawLicense.toLowerCase() == 'student' ? 'Student' : 'Pilot';
          _selectedSchoolId = profile.mainSchoolId;
          
          _birthday = profile.birthday;
          final birthdayText = _birthday != null ? DateFormat('yyyy-MM-dd').format(_birthday!) : '';
          
          // Controller frissítése csak setState blokkon belül, ha a dátumot állítottuk
          if (_birthdayController.text != birthdayText) {
               _birthdayController.text = birthdayText;
          }
      });

      // Frissítjük a Controller-eket, de CSAK akkor, ha az új érték eltér a Controller aktuális tartalmától.
      if (_familyNameController.text != profile.familyname) {
          _familyNameController.text = profile.familyname;
      }
      if (_forenameController.text != profile.forename) {
          _forenameController.text = profile.forename;
      }
      // Update _selectedSchoolId from stream; safe now since license change no longer clears it
      if (_selectedSchoolId != profile.mainSchoolId) {
          setState(() => _selectedSchoolId = profile.mainSchoolId);
      }
      if (_nicknameController.text != (profile.nickname ?? '')) {
          _nicknameController.text = profile.nickname ?? '';
      }
      if (_phoneController.text != (profile.phonenumber ?? '')) {
          _phoneController.text = profile.phonenumber ?? '';
      }
      if (_address1Controller.text != (profile.address1 ?? '')) {
          _address1Controller.text = profile.address1 ?? '';
      }
      if (_address2Controller.text != (profile.address2 ?? '')) {
          _address2Controller.text = profile.address2 ?? '';
      }
      if (_address3Controller.text != (profile.address3 ?? '')) {
          _address3Controller.text = profile.address3 ?? '';
      }
      if (_emergencyNameController.text != profile.emergencyContactName) {
          _emergencyNameController.text = profile.emergencyContactName;
      }
      // ignore: dead_null_aware_expression
      if (_emergencyPhoneController.text != (profile.emergencyContactPhone ?? '')) {
          // ignore: dead_null_aware_expression
          _emergencyPhoneController.text = profile.emergencyContactPhone ?? '';
      }
      // ignore: dead_null_aware_expression
      if (_gliderController.text != (profile.glider ?? '')) {
          _gliderController.text = profile.glider ?? '';
      }
      // ignore: dead_null_aware_expression
      if (_shvNumberController.text != (profile.shvnumber ?? '')) {
          _shvNumberController.text = profile.shvnumber ?? '';
      }

      _suppressAutoSave = false;
  }
  
  // Eredeti _loadProfile, amelyet CSAK az első inicializáláskor hívunk meg
  void _loadProfile(UserProfile profile, {bool forceSync = false}) {
    
    _suppressAutoSave = true;

    // Mindig állítsuk be a kontrollereket, mert ez csak az első inicializálás.
    _familyNameController.text = profile.familyname;
    _forenameController.text = profile.forename;
    _nicknameController.text = profile.nickname ?? '';
    _phoneController.text = profile.phonenumber ?? '';
    
    _selectedNationality = profile.nationality;
    _address1Controller.text = profile.address1 ?? '';
    _address2Controller.text = profile.address2 ?? '';
    _address3Controller.text = profile.address3 ?? '';
    _selectedCountry = profile.address4;
    _emergencyNameController.text = profile.emergencyContactName;
    _emergencyPhoneController.text = profile.emergencyContactPhone;

    _height = (profile.height != null && profile.height! > 0) ? profile.height!.toDouble() : 170.0;
    _weight = (profile.weight != null && profile.weight! > 0) ? profile.weight!.toDouble() : 65.0;

    _gliderController.text = profile.glider ?? '';
    _shvNumberController.text = profile.shvnumber ?? '';

    // Normalize license value (convert old lowercase to new capitalized format)
    final rawLicense = profile.license ?? 'Student';
    _selectedLicense = rawLicense.toLowerCase() == 'student' ? 'Student' : 'Pilot';
    _selectedSchoolId = profile.mainSchoolId;
    
    _birthday = profile.birthday;
    final birthdayText = _birthday != null ? DateFormat('yyyy-MM-dd').format(_birthday!) : '';
    _birthdayController.text = birthdayText;

    // setState az állapothoz kötött elemek frissítéséhez
    setState(() {
      _height = _height;
      _weight = _weight;
      _selectedLicense = _selectedLicense;
      _selectedSchoolId = _selectedSchoolId;
      _selectedNationality = _selectedNationality;
      _selectedCountry = _selectedCountry;
      _birthday = _birthday;
    });

    _suppressAutoSave = false;
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initialDate = _birthday ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _birthday = picked;
        _birthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
      _autoSaveProfile();
    }
  }

  void _autoSaveProfile() {
    if (_suppressAutoSave) return;
    final service = context.read<ProfileService>();
    final profile = service.userProfile;
    
    if (profile == null || !_formInitialized) return;

    final updated = UserProfile(
      uid: profile.uid,
      email: profile.email,
      familyname: _familyNameController.text.trim(),
      forename: _forenameController.text.trim(),
      nickname: _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
      phonenumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      birthday: _birthday,
      nationality: _selectedNationality,
      address1: _address1Controller.text.trim().isEmpty ? null : _address1Controller.text.trim(),
      address2: _address2Controller.text.trim().isEmpty ? null : _address2Controller.text.trim(),
      address3: _address3Controller.text.trim().isEmpty ? null : _address3Controller.text.trim(),
      address4: _selectedCountry,
      emergencyContactName: _emergencyNameController.text.trim(),
      emergencyContactPhone: _emergencyPhoneController.text.trim(),
      height: _height.round(),
      weight: _weight.round(),
      glider: _gliderController.text.trim().isEmpty ? null : _gliderController.text.trim(),
      shvnumber: _shvNumberController.text.trim().isEmpty ? null : _shvNumberController.text.trim(),
      license: _selectedLicense,
      mainSchoolId: _selectedSchoolId,
    );

    // Silent auto-save
    service.updateProfile(updated);
  }

  Future<void> _changePassword(String lang) async {
    // Validate both password fields are not empty
    if (_oldPasswordController.text.trim().isEmpty || _newPasswordController.text.trim().isEmpty) {
      _showSnack(_t('Empty_Password_Fields', lang));
      return;
    }

    try {
      final service = context.read<ProfileService>();
      await service.changePassword(_oldPasswordController.text, _newPasswordController.text);
      
      // Clear password fields on success
      _oldPasswordController.clear();
      _newPasswordController.clear();
      
      // Show success message
      _showSnack(_t('Password_Success', lang));
    } catch (e) {
      // Show error message
      _showSnack(_t('Password_Error', lang));
    }
  }

  void _setupSyncListener() {
    final notifier = context.read<ProfileService>().syncSuccessNotifier;
    _syncNotifier = notifier;
    _lastSeenSyncTick = notifier.value;
    _syncListener = () {
      final current = notifier.value;
      if (current != _lastSeenSyncTick) {
        _lastSeenSyncTick = current;
        // Az alábbi sor KIVÉVE, ahogy kérted, hogy ne villanjon fel a "Synced with cloud" üzenet.
        // final lang = context.read<AppConfigService>().currentLanguageCode;
        // _showSnack(_t('Synced_Cloud', lang), backgroundColor: Colors.green);
      }
    };
    notifier.addListener(_syncListener!);
  }

  void _showSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Ensure rebuild when ProfileService changes
    final service = context.watch<ProfileService>();
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final profile = service.userProfile;

    // Profile is guaranteed to be non-null at this point because
    // the SplashScreen waits for ProfileService.waitForInitialData() before navigation
    if (profile == null) {
      // Fallback (should rarely happen, but kept as safety)
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Form(
        key: _formKey,
        child: ResponsiveListView(
          children: [
              _buildSection(
                title: _t('Personal_Details', lang),
                children: [
                  _buildTextField(
                    label: _t('Family_Name', lang),
                    controller: _familyNameController,
                    validator: _requiredValidator,
                  ),
                  _buildTextField(
                    label: _t('Forename', lang),
                    controller: _forenameController,
                    validator: _requiredValidator,
                  ),
                  _buildTextField(
                    label: _t('Nickname', lang),
                    controller: _nicknameController,
                  ),
                  _buildDateField(lang),
                  _buildTextField(
                    label: _t('Email_Address', lang),
                    initialValue: profile.email,
                    readOnly: true,
                    // visually greyed out
                    inputFormatters: [],
                  ),
                  _buildTextField(
                    label: _t('Phone_Number', lang),
                    controller: _phoneController,
                    validator: _requiredValidator,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[0-9+]*$'))],
                  ),
                  _buildCountryDropdown(_t('Nationality', lang), _selectedNationality, (value) {
                    setState(() => _selectedNationality = value);
                    _autoSaveProfile();
                  }),
                  _buildHeightPicker(lang),
                  _buildWeightPicker(lang),
                ],
              ),
              _buildSection(
                title: _t('Address', lang),
                children: [
                  _buildTextField(
                    label: _t('Street_Nr', lang),
                    controller: _address1Controller,
                    validator: _requiredValidator,
                  ),
                  _buildTextField(
                    label: _t('ZIP', lang),
                    controller: _address2Controller,
                  ),
                  _buildTextField(
                    label: _t('City', lang),
                    controller: _address3Controller,
                  ),
                  _buildCountryDropdown(_t('Country', lang), _selectedCountry, (value) {
                    setState(() => _selectedCountry = value);
                    _autoSaveProfile();
                  }),
                ],
              ),
              _buildSection(
                title: _t('Emergency_Contact', lang),
                children: [
                  _buildTextField(
                    label: _t('Full_Name', lang),
                    controller: _emergencyNameController,
                    validator: _requiredValidator,
                  ),
                  _buildTextField(
                    label: _t('Phone_Number', lang),
                    controller: _emergencyPhoneController,
                    validator: _requiredValidator,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[0-9+]*$'))],
                  ),
                ],
              ),
              _buildSection(
                title: _t('License_Equipment', lang),
                children: [
                  _buildLicenseDropdown(profile.license, lang),
                  if (_selectedLicense == 'Student') _buildSchoolDropdown(lang),
                  _buildTextField(
                    label: _t('SHV_Number', lang),
                    controller: _shvNumberController,
                  ),
                  _buildTextField(
                    label: _t('Glider', lang),
                    controller: _gliderController,
                  ),
                ],
              ),
              _buildSection(
                title: _t('Change_Password', lang),
                children: [
                  _buildPasswordField(
                    label: _t('Old_Password', lang),
                    controller: _oldPasswordController,
                    obscureText: _obscureOldPassword,
                    onToggleVisibility: () => setState(() => _obscureOldPassword = !_obscureOldPassword),
                  ),
                  _buildPasswordField(
                    label: _t('New_Password', lang),
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    onToggleVisibility: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _changePassword(lang),
                      child: Text(_t('Change_Password', lang)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    final theme = Theme.of(context);
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Text(title, style: theme.textTheme.titleMedium),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (final child in children) ...[child, const SizedBox(height: 12)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    TextEditingController? controller,
    String? initialValue,
    bool readOnly = false,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      readOnly: readOnly,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: readOnly
          ? theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor)
          : theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: readOnly ? theme.disabledColor.withValues(alpha: 0.08) : theme.cardColor,
      ),
    );
  }

  Widget _buildDateField(String lang) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: _pickBirthday,
      child: AbsorbPointer(
        child: TextFormField(
          controller: _birthdayController,
          decoration: InputDecoration(
            labelText: _t('Date_of_Birth', lang),
            filled: true,
            fillColor: theme.cardColor,
            suffixIcon: const Icon(Icons.calendar_today),
          ),
        ),
      ),
    );
  }

  Widget _buildHeightPicker(String lang) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_t('Height', lang)}: ${_height.round()} cm', style: theme.textTheme.bodyMedium),
        Slider(
          value: _height,
          min: 150,
          max: 210,
          divisions: 60,
          label: '${_height.round()} cm',
          onChanged: (value) {
            setState(() => _height = value);
            _autoSaveProfile();
          },
        ),
      ],
    );
  }

  Widget _buildWeightPicker(String lang) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_t('Weight', lang)}: ${_weight.round()} kg', style: theme.textTheme.bodyMedium),
        Slider(
          value: _weight,
          min: 45,
          max: 110,
          divisions: 65,
          label: '${_weight.round()} kg',
          onChanged: (value) {
            setState(() => _weight = value);
            _autoSaveProfile();
          },
        ),
      ],
    );
  }

  Widget _buildCountryDropdown(String label, String? currentValue, void Function(String?) onChanged) {
    final theme = Theme.of(context);
    
    // Filter out top countries from the main list to avoid duplicates
    final restOfWorld = _allCountries.where((c) => !_topCountries.contains(c)).toList();
    
    // Build the complete list of all valid country values
    final allValidCountries = [..._topCountries, ...restOfWorld];
    
    // If currentValue is not in our list, set to null to avoid dropdown assertion error
    final safeValue = (currentValue != null && allValidCountries.contains(currentValue)) 
        ? currentValue 
        : null;
    
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.cardColor,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          hint: const Text('Select...'),
          items: [
            // Top countries section
            ..._topCountries.map((country) {
              return DropdownMenuItem(value: country, child: Text(country));
            }),
            // Divider - use null value so it can be a visual separator
            const DropdownMenuItem<String>(
              enabled: false,
              value: null, 
              child: Divider(),
            ),
            // Rest of world section
            ...restOfWorld.map((country) {
              return DropdownMenuItem(value: country, child: Text(country));
            }),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.cardColor,
        suffixIcon: IconButton(
          icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggleVisibility,
        ),
      ),
    );
  }

  Widget _buildLicenseDropdown(String? currentLicense, String lang) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: _t('License', lang),
        filled: true,
        fillColor: theme.cardColor,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedLicense,
          items: [
            DropdownMenuItem(value: 'Student', child: Text(_t('Student', lang))),
            DropdownMenuItem(value: 'Pilot', child: Text(_t('Pilot', lang))),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedLicense = value;
              // IMPORTANT: Do NOT clear _selectedSchoolId when changing license.
              // mainSchoolId is independent of license and should be preserved.
              // It only changes if the user explicitly selects a new school.
            });
            _autoSaveProfile();
          },
        ),
      ),
    );
  }

  Widget _buildSchoolDropdown(String lang) {
    final theme = Theme.of(context);
    final schools = context.watch<ProfileService>().schools;
    final normalizedSelected = schools.any((s) => s['id'] == _selectedSchoolId)
        ? _selectedSchoolId
        : null;
    final schoolNames = schools.map((s) => s['name'] as String? ?? '').toList();
    final idByName = {for (var s in schools) (s['name'] as String? ?? ''): s['id']};
    final selectedName = schools.firstWhere(
      (s) => s['id'] == _selectedSchoolId,
      orElse: () => <String, String>{},
    )['name'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Autocomplete<String>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text == '') {
            return schoolNames;
          }
          return schoolNames.where((String option) =>
              option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
        },
        displayStringForOption: (option) => option,
        initialValue: TextEditingValue(text: selectedName ?? ''),
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextFormField(
            controller: controller,
            focusNode: focusNode,
            readOnly: false,
            decoration: InputDecoration(
              labelText: _t('School', lang),
              filled: true,
              fillColor: theme.cardColor,
              hintText: _t('Select_School', lang),
            ),
            validator: (value) {
              if (value == null || value.isEmpty || !schoolNames.contains(value)) {
                return _t('Select_School', lang);
              }
              return null;
            },
            onChanged: (value) {
              // Only allow valid schools
              if (schoolNames.contains(value)) {
                setState(() {
                  _selectedSchoolId = idByName[value];
                });
                _autoSaveProfile();
              }
            },
          );
        },
        onSelected: (String selection) {
          setState(() {
            _selectedSchoolId = idByName[selection];
          });
          _autoSaveProfile();
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              child: SizedBox(
                height: 200.0,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      title: Text(option),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _t('Required_Field', context.read<AppConfigService>().currentLanguageCode);
    }
    return null;
  }

}

