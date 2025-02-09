import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:mixin_bot_sdk_dart/mixin_bot_sdk_dart.dart';

import '../../account/account_key_value.dart';
import '../../account/account_server.dart';
import '../../crypto/signal/signal_database.dart';
import '../../utils/extension/extension.dart';
import '../../utils/hive_key_values.dart';
import '../../utils/hook.dart';
import '../../utils/mixin_api_client.dart';
import '../../utils/system/package_info.dart';
import '../../widgets/dialog.dart';
import '../../widgets/toast.dart';
import '../home/bloc/multi_auth_cubit.dart';
import 'landing_mobile.dart';
import 'landing_qrcode.dart';

enum LandingMode {
  qrcode,
  mobile,
}

class LandingModeCubit extends Cubit<LandingMode> {
  LandingModeCubit() : super(LandingMode.qrcode);

  void changeMode(LandingMode mode) => emit(mode);
}

class LandingPage extends HookWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountServerError = context.watch<AsyncSnapshot<AccountServer>?>();

    final modeCubit = useBloc(LandingModeCubit.new);
    final mode = useBlocState<LandingModeCubit, LandingMode>(bloc: modeCubit);

    Widget child;
    switch (mode) {
      case LandingMode.qrcode:
        child = const LandingQrCodeWidget();
        break;
      case LandingMode.mobile:
        child = const LoginWithMobileWidget();
        break;
    }
    if (accountServerError?.hasError ?? false) {
      child = const _LoginFailed();
    }
    return BlocProvider.value(
      value: modeCubit,
      child: _LandingScaffold(child: child),
    );
  }
}

class _LoginFailed extends HookWidget {
  const _LoginFailed();

  @override
  Widget build(BuildContext context) {
    final accountServerError = context.read<AsyncSnapshot<AccountServer>?>()!;
    final errorText = 'Error: ${accountServerError.error}';
    final stackTraceText = 'StackTrace: ${accountServerError.stackTrace}';

    return Padding(
      padding: const EdgeInsets.only(top: 56, bottom: 30, right: 48, left: 48),
      child: Column(
        children: [
          Text(
            context.l10n.unknowError,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.theme.red,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DefaultTextStyle(
              style: TextStyle(
                color: context.theme.text,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              child: SelectionArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.theme.sidebarSelected,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          Text(errorText),
                          Text(stackTraceText),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 42),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MixinButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 56,
                  vertical: 14,
                ),
                backgroundTransparent: true,
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: '$errorText\n$stackTraceText'));
                  showToastSuccessful();
                },
                child: Text(context.l10n.copy),
              ),
              MixinButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 56,
                  vertical: 14,
                ),
                onTap: () async {
                  final multiAuthCubit = context.read<MultiAuthCubit>();
                  final authState = multiAuthCubit.state.current;
                  if (authState == null) return;

                  await createClient(
                    userId: authState.account.userId,
                    sessionId: authState.account.sessionId,
                    privateKey: authState.privateKey,
                    loginByPhoneNumber:
                        AccountKeyValue.instance.primarySessionId == null,
                  )
                      .accountApi
                      .logout(LogoutRequest(authState.account.sessionId));
                  await clearKeyValues();
                  await SignalDatabase.get.clear();
                  multiAuthCubit.signOut();
                },
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LandingScaffold extends HookWidget {
  const _LandingScaffold({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final info = useMemoizedFuture(getPackageInfo, null).data;
    return Portal(
      child: Scaffold(
        backgroundColor: context.dynamicColor(
          const Color(0xFFE5E5E5),
          darkColor: const Color.fromRGBO(35, 39, 43, 1),
        ),
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Center(
              child: SizedBox(
                width: 520,
                height: 418,
                child: Material(
                  color: context.theme.popUp,
                  borderRadius: const BorderRadius.all(Radius.circular(13)),
                  elevation: 10,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(13)),
                    child: child,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: Text(
                info?.versionAndBuildNumber ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: context.theme.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LandingModeSwitchButton extends HookWidget {
  const LandingModeSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = useBlocState<LandingModeCubit, LandingMode>();
    final String buttonText;
    switch (mode) {
      case LandingMode.qrcode:
        buttonText = context.l10n.signWithPhoneNumber;
        break;
      case LandingMode.mobile:
        buttonText = context.l10n.signWithQrcode;
        break;
    }
    return TextButton(
      onPressed: () {
        final modeCubit = context.read<LandingModeCubit>();
        switch (mode) {
          case LandingMode.qrcode:
            modeCubit.changeMode(LandingMode.mobile);
            break;
          case LandingMode.mobile:
            modeCubit.changeMode(LandingMode.qrcode);
            break;
        }
      },
      child: Text(
        buttonText,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: context.theme.accent,
        ),
      ),
    );
  }
}
