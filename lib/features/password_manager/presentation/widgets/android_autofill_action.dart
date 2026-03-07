import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';

import '../../../../../core/theme/app_icons.dart';

class AndroidAutofillAction extends StatelessWidget {
  const AndroidAutofillAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: 'Enable Android Autofill',
      icon: const Icon(AppIcons.magic),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final service = AutofillService();
        final status = await service.status;

        if (status == AutofillServiceStatus.unsupported) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Android Autofill is not supported on this device.',
              ),
            ),
          );
          return;
        }

        if (status == AutofillServiceStatus.enabled) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Autofill service already enabled.')),
          );
          return;
        }

        await service.requestSetAutofillService();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Select this app as your Android Autofill service.'),
          ),
        );
      },
    );
  }
}
