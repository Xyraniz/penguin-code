import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';

void main() {
  test('keeps the manually configured model available after discovery', () {
    const provider = ProviderProfile(
      id: 'local',
      name: 'Local server',
      model: 'custom-model',
      endpoint: 'http://127.0.0.1:11434/v1',
      onDevice: true,
      models: [ModelProfile(id: 'other-model')],
    );

    expect(
      provider.availableModels.map((model) => model.id),
      ['custom-model', 'other-model'],
    );
  });

  test('uses the discovered display name in the provider route label', () {
    const provider = ProviderProfile(
      id: 'remote',
      name: 'Remote API',
      model: 'model-id',
      endpoint: 'https://api.example.test/v1',
      onDevice: false,
      models: [ModelProfile(id: 'model-id', name: 'Model name')],
    );

    expect(provider.routeLabel, 'Remote API · Model name');
  });
}
