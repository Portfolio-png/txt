import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/groups/data/repositories/api_group_repository.dart';
import 'package:paper/features/groups/domain/group_inputs.dart';
import 'package:paper/features/groups/presentation/providers/groups_provider.dart';

void main() {
  setUp(() {
    ApiGroupRepository.debugResetMockStore();
  });

  test('mock repository preserves parent and unit relationships', () async {
    final repository = ApiGroupRepository(useMockResponses: true);

    await repository.init();
    final seeded = await repository.getGroups();
    expect(seeded.any((group) => group.name == 'Paper'), isTrue);
    expect(seeded.any((group) => group.parentGroupId != null), isTrue);

    final created = await repository.createGroup(
      const CreateGroupInput(name: 'Brown', parentGroupId: 2, unitId: 2),
    );
    final updated = await repository.updateGroup(
      UpdateGroupInput(
        id: created.id,
        name: 'Brown Premium',
        parentGroupId: 1,
        unitId: 1,
      ),
    );
    final archived = await repository.archiveGroup(updated.id);
    final restored = await repository.restoreGroup(updated.id);

    expect(updated.parentGroupId, 1);
    expect(updated.unitId, 1);
    expect(archived.isArchived, isTrue);
    expect(restored.isArchived, isFalse);
  });

  test(
    'mock repository prevents archiving a group with active children',
    () async {
      final repository = ApiGroupRepository(useMockResponses: true);

      await repository.init();

      expect(
        () => repository.archiveGroup(1),
        throwsA(
          isA<GroupApiException>().having(
            (error) => error.message,
            'message',
            contains('active child groups'),
          ),
        ),
      );
    },
  );

  test(
    'groups provider filters, checks duplicates, and blocks invalid archive',
    () async {
      final provider = GroupsProvider(
        repository: ApiGroupRepository(useMockResponses: true),
      );

      await provider.initialize();

      expect(provider.groups.first.isArchived, isFalse);
      expect(provider.groups.last.isArchived, isTrue);

      provider.setSearchQuery('kraft');
      expect(provider.filteredGroups.map((group) => group.name), ['Kraft']);

      provider.setSearchQuery('');
      provider.setStatusFilter(GroupStatusFilter.archived);
      expect(provider.filteredGroups.map((group) => group.name), [
        'Legacy Group',
      ]);

      final duplicate = provider.checkDuplicate(
        name: 'Kraft',
        parentGroupId: 1,
      );
      final allowed = provider.checkDuplicate(name: 'Kraft', parentGroupId: 3);
      expect(duplicate.blockingDuplicate, isTrue);
      expect(allowed.blockingDuplicate, isFalse);

      expect(provider.wouldCreateCycle(groupId: 1, parentGroupId: 2), isTrue);
      expect(provider.wouldCreateCycle(groupId: 2, parentGroupId: 1), isFalse);

      final result = await provider.archiveGroup(1);
      expect(result, isNull);
      expect(provider.errorMessage, contains('active child groups'));
    },
  );
}
