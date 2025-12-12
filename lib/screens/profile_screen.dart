import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/profile_service.dart';
import '../services/app_config_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
  bool _dialogShown = false;
  bool _formInitialized = false;
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;

  // Top countries for quick access
  static const List<String> _topCountries = [
    'Austria', 'China', 'Germany', 'Hungary', 'India', 'Poland', 'Switzerland', 'United States of America'
  ];

  // Rest of world countries
  static const List<String> _allCountries = [
    'Afghanistan', 'Albania', 'Algeria', 'Andorra', 'Angola', 'Antigua and Barbuda', 'Argentina', 'Armenia',
    'Australia', 'Azerbaijan', 'Bahamas', 'Bahrain', 'Bangladesh', 'Barbados', 'Belarus', 'Belgium',
    'Belize', 'Benin', 'Bhutan', 'Bolivia', 'Bosnia and Herzegovina', 'Botswana', 'Brazil', 'Brunei', 'Bulgaria',
    'Burkina Faso', 'Burundi', 'Cambodia', 'Cameroon', 'Canada', 'Cape Verde', 'Central African Republic', 'Chad',
    'Chile', 'Colombia', 'Comoros', 'Congo', 'Costa Rica', 'Croatia', 'Cuba', 'Cyprus', 'Czech Republic',
    'Denmark', 'Djibouti', 'Dominica', 'Dominican Republic', 'East Timor', 'Ecuador', 'Egypt', 'El Salvador',
    'Equatorial Guinea', 'Eritrea', 'Estonia', 'Ethiopia', 'Fiji', 'Finland', 'France', 'Gabon', 'Gambia', 'Georgia',
    'Ghana', 'Greece', 'Grenada', 'Guatemala', 'Guinea', 'Guinea-Bissau', 'Guyana', 'Haiti', 'Honduras',
    'Iceland', 'Indonesia', 'Iran', 'Iraq', 'Ireland', 'Israel', 'Italy', 'Ivory Coast', 'Jamaica',
    'Japan', 'Jordan', 'Kazakhstan', 'Kenya', 'Kiribati', 'North Korea', 'South Korea', 'Kuwait', 'Kyrgyzstan', 'Laos',
    'Latvia', 'Lebanon', 'Lesotho', 'Liberia', 'Libya', 'Liechtenstein', 'Lithuania', 'Luxembourg', 'Macedonia',
    'Madagascar', 'Malawi', 'Malaysia', 'Maldives', 'Mali', 'Malta', 'Marshall Islands', 'Mauritania', 'Mauritius',
    'Mexico', 'Micronesia', 'Moldova', 'Monaco', 'Mongolia', 'Montenegro', 'Morocco', 'Mozambique', 'Myanmar', 'Namibia',
    'Nauru', 'Nepal', 'Netherlands', 'New Zealand', 'Nicaragua', 'Niger', 'Nigeria', 'Norway', 'Oman', 'Pakistan',
    'Palau', 'Panama', 'Papua New Guinea', 'Paraguay', 'Peru', 'Philippines', 'Portugal', 'Qatar', 'Romania',
    'Russia', 'Rwanda', 'Saint Kitts and Nevis', 'Saint Lucia', 'Saint Vincent and the Grenadines', 'Samoa', 'San Marino',
    'Sao Tome and Principe', 'Saudi Arabia', 'Senegal', 'Serbia', 'Seychelles', 'Sierra Leone', 'Singapore', 'Slovakia',
    'Slovenia', 'Solomon Islands', 'Somalia', 'South Africa', 'South Sudan', 'Spain', 'Sri Lanka', 'Sudan', 'Suriname',
    'Swaziland', 'Sweden', 'Syria', 'Taiwan', 'Tajikistan', 'Tanzania', 'Thailand', 'Togo', 'Tonga',
    'Trinidad and Tobago', 'Tunisia', 'Turkey', 'Turkmenistan', 'Tuvalu', 'Uganda', 'Ukraine', 'United Arab Emirates',
    'United Kingdom', 'Uruguay', 'Uzbekistan', 'Vanuatu', 'Vatican City', 'Venezuela', 'Vietnam',
    'Yemen', 'Zambia', 'Zimbabwe'
  ];

  // Localization map
  static const Map<String, Map<String, String>> _texts = {
    'Personal_Details': {'en': 'Personal Details', 'de': 'Persönliche Angaben'},
    'Contact_Details': {'en': 'Contact Details', 'de': 'Kontaktangaben'},
    'Emergency_Contact': {'en': 'Emergency Contact (Required)', 'de': 'Notfallkontakt (Erforderlich)'},
    'Other_Info': {'en': 'Other Info', 'de': 'Sonstige Informationen'},
    'Change_Password': {'en': 'Change Password', 'de': 'Passwort ändern'},
    'Family_Name': {'en': 'Family Name', 'de': 'Familienname'},
    'Forename': {'en': 'Forename', 'de': 'Vorname'},
    'Nickname': {'en': 'Nickname', 'de': 'Spitzname'},
    'Date_of_Birth': {'en': 'Date of Birth', 'de': 'Geburtsdatum'},
    'Phone_Number': {'en': 'Phone Number', 'de': 'Telefonnummer'},
    'Email_Address': {'en': 'Email Address', 'de': 'E-Mail-Adresse'},
    'Nationality': {'en': 'Nationality', 'de': 'Nationalität'},
    'Street_Nr': {'en': 'Street & Nr', 'de': 'Straße & Nr.'},
    'ZIP': {'en': 'ZIP', 'de': 'PLZ'},
    'City': {'en': 'City', 'de': 'Stadt'},
    'Country': {'en': 'Country', 'de': 'Land'},
    'Full_Name': {'en': 'Full Name', 'de': 'Voller Name'},
    'Glider': {'en': 'Glider', 'de': 'Gleitschirm'},
    'SHV_Number': {'en': 'SHV Number', 'de': 'SHV Nummer'},
    'Old_Password': {'en': 'Old Password', 'de': 'Altes Passwort'},
    'New_Password': {'en': 'New Password', 'de': 'Neues Passwort'},
    'Required_Field': {'en': 'Required', 'de': 'Erforderlich'},
    'Save': {'en': 'Save', 'de': 'Speichern'},
    'Password_Success': {'en': 'Password changed!', 'de': 'Passwort geändert!'},
    'Profile_Saved_Offline': {'en': 'Data saved to cache (Offline)', 'de': 'Daten im Cache gespeichert (Offline)'},
    'Profile_Saved_Online': {'en': 'Profile saved successfully', 'de': 'Profil erfolgreich gespeichert'},
    'Height': {'en': 'Height', 'de': 'Größe'},
    'Weight': {'en': 'Weight', 'de': 'Gewicht'},
    'License': {'en': 'License', 'de': 'Lizenz'},
    'School': {'en': 'School', 'de': 'Schule'},
    'Student': {'en': 'Student', 'de': 'Schüler'},
    'Pilot': {'en': 'Pilot', 'de': 'Pilot'},
    'Select_School': {'en': 'Select school', 'de': 'Schule auswählen'},
    'Password_Error': {'en': 'Error changing password', 'de': 'Fehler beim Ändern des Passworts'},
    'Empty_Password_Fields': {'en': 'Both password fields are required', 'de': 'Beide Passwortfelder sind erforderlich'},
  };

  String _t(String key, String lang) {
    return _texts[key]?[lang] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _attachChangeListeners();
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.watch<ProfileService>();
    final profile = service.userProfile;

    if (profile != null && !_formInitialized) {
      _loadProfile(profile);
    }

    if (!_dialogShown && !service.isLoading && profile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final svc = context.read<ProfileService>();
        if (!svc.isProfileComplete()) {
          _showProfileIncompleteDialog();
        }
        _dialogShown = true;
      });
    }
  }

  void _loadProfile(UserProfile profile) {
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
    final rawLicense = profile.license ?? 'student';
    _selectedLicense = rawLicense.toLowerCase() == 'student' ? 'Student' : 'Pilot';
    _selectedSchoolId = profile.schoolId;
    _birthday = profile.birthday;
    _birthdayController.text = _birthday != null ? DateFormat('yyyy-MM-dd').format(_birthday!) : '';

    _formInitialized = true;
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
      schoolId: _selectedLicense == 'Student' ? _selectedSchoolId : null,
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showProfileIncompleteDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: const Text('Profile Incomplete'),
          content: const Text('Please complete all required profile fields.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.watch<ProfileService>();
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final profile = service.userProfile;

    if (service.isLoading && profile == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
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
                ],
              ),
              _buildSection(
                title: _t('Contact_Details', lang),
                children: [
                  _buildTextField(
                    label: _t('Email_Address', lang),
                    initialValue: profile?.email ?? '',
                    readOnly: true,
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
                title: _t('Other_Info', lang),
                children: [
                  _buildHeightPicker(lang),
                  _buildWeightPicker(lang),
                  _buildTextField(
                    label: _t('Glider', lang),
                    controller: _gliderController,
                  ),
                  _buildTextField(
                    label: _t('SHV_Number', lang),
                    controller: _shvNumberController,
                  ),
                  _buildLicenseDropdown(profile?.license, lang),
                  if (_selectedLicense == 'Student') _buildSchoolDropdown(lang),
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
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.cardColor,
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
    
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.cardColor,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          items: [
            // Top countries section
            ..._topCountries.map((country) {
              return DropdownMenuItem(value: country, child: Text(country));
            }),
            // Divider
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
              if (_selectedLicense != 'Student') {
                _selectedSchoolId = null;
              }
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
    return InputDecorator(
      decoration: InputDecoration(
        labelText: _t('School', lang),
        filled: true,
        fillColor: theme.cardColor,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedSchoolId,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(_t('Select_School', lang))),
            ...schools.map((s) => DropdownMenuItem<String?>(
                  value: s['id'],
                  child: Text(s['name'] ?? 'Unknown'),
                )),
          ],
          onChanged: (value) {
            setState(() => _selectedSchoolId = value);
            _autoSaveProfile();
          },
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }
}
