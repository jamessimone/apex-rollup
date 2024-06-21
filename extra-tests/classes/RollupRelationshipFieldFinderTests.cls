@IsTest
private class RollupRelationshipFieldFinderTests {
  static final RollupControl__mdt control = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 10000);
  static final Set<String> uniqueFieldNames = new Set<String>{ 'Id', 'Name' };

  @TestSetup
  static void setup() {
    insert new Account(Name = RollupRelationshipFieldFinderTests.class.getName());
  }

  @IsTest
  static void shouldFindParentRelationshipBetweenStandardObjects() {
    Account parent = [SELECT Id FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(ParentId = parent.Id, Name = 'Child cpa');
    insert cpa;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    parent = (Account) RollupTestUtils.queryRecord(parent.Id);
    System.assertEquals(parent, traversal.retrieveParents(cpa.Id)[0]);

    // validates that the relationship field finder works even if a fully qualified path isn't provided if the parent
    // is "just" the next level up
    finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    System.assertEquals(parent, traversal.retrieveParents(cpa.Id)[0]);
  }

  @IsTest
  static void shouldFindGrandparentRelationshipBetweenStandardObjects() {
    Account parent = [SELECT Id FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(ParentId = parent.Id, Name = 'Child looking up to account');
    insert cpa;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      User.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    parent = [SELECT OwnerId FROM Account WHERE Id = :parent.Id];
    User expectedUser = (User) RollupTestUtils.queryRecord(parent.OwnerId);
    System.assertEquals(expectedUser, traversal.retrieveParents(cpa.Id)[0], 'User should have been retrieved correctly!');
  }

  @IsTest
  static void shouldBailEarlyIfQueryCountExceedsControlCount() {
    Account acc = [SELECT Id FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, Name = 'Child cpa');
    control.MaxNumberOfQueries__c = 1;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      User.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<ContactPointAddress>{ cpa });

    System.assertEquals(false, traversal.getIsFinished(), 'Should have bailed early!');
  }

  @IsTest
  static void skipsIntermediateRelationshipFetchesForFullRecalc() {
    // same as above except this one should succeed since everything should be fetched in one go
    Account acc = [SELECT Id, OwnerId, Owner.Name FROM Account];

    Contact con = new Contact(AccountId = acc.Id, LastName = 'Child con');
    insert con;
    control.MaxNumberOfQueries__c = 1;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Account.Owner.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      User.SObjectType,
      new Map<Id, SObject>()
    );
    finder.setIsFullRecalc(true);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Contact>{ con });

    System.assertEquals(true, traversal.getParentLookupToRecords().containsKey(acc.OwnerId));
    System.assertEquals(acc.Owner.Name, traversal.retrieveParents(con.Id)[0].get('Name'));
    System.assertEquals(true, traversal.getIsFinished());
  }

  @IsTest
  static void fullRecalcDoesNotBlowUpOnParentFields() {
    Account acc = [SELECT Id, OwnerId, Owner.Name FROM Account];

    Contact con = new Contact(AccountId = acc.Id, LastName = 'Child con');
    Contact nonParentedContact = new Contact(LastName = 'Non parent');
    List<Contact> contacts = new List<Contact>{ con, nonParentedContact };
    insert contacts;
    contacts = [SELECT Id FROM Contact WHERE Id = :contacts];

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Account.Owner.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      User.SObjectType,
      new Map<Id, SObject>()
    );
    finder.setIsFullRecalc(true);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(contacts);

    System.assertEquals(true, traversal.getParentLookupToRecords().containsKey(acc.OwnerId));
    System.assertEquals(acc.Owner.Name, traversal.retrieveParents(con.Id)[0].get('Name'));
    System.assertEquals(true, traversal.getIsFinished());
  }

  @IsTest
  static void fullRecalcDoesNotBlowUpOnDynamicParentFields() {
    Account acc = [SELECT Id, OwnerId, Owner.Name FROM Account];

    ContactPointAddress child = new ContactPointAddress(ParentId = acc.Id, Name = 'Child');
    insert child;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      new Set<String>{ 'ParentId, Name' },
      uniqueFieldNames,
      User.SObjectType,
      new Map<Id, SObject>()
    );
    finder.setIsFullRecalc(true);
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<ContactPointAddress>{ child });

    System.assertEquals(true, traversal.getParentLookupToRecords().containsKey(acc.OwnerId));
    System.assertEquals(acc.Owner.Name, traversal.retrieveParents(child.Id)[0].get('Name'));
    System.assertEquals(true, traversal.getIsFinished());
  }

  @IsTest
  static void shouldNotReportFalsePositiveIfUltimateParentStaysTheSame() {
    Account intermediateOne = new Account(Name = 'Intermediate 1');
    Account intermediateTwo = new Account(Name = 'Intermediate 2');
    insert new List<Account>{ intermediateOne, intermediateTwo };

    Set<Id> accountIds = new Set<Id>{ intermediateOne.Id, intermediateTwo.Id };
    List<Account> updatedAccounts = [SELECT Id, OwnerId, Name FROM Account WHERE Id = :accountIds];
    if (updatedAccounts.size() == 2) {
      // don't run the rest of the test if the org has some kind of ownership assignment going on that would invalidate
      // the results
      Account one = updatedAccounts[0];
      Account two = updatedAccounts[1];
      if (one.OwnerId != two.OwnerId) {
        return;
      } else {
        intermediateOne = one.Id == intermediateOne.Id ? one : two;
        intermediateTwo = two.Id == intermediateTwo.Id ? two : one;
      }
    }

    ContactPointAddress cpa = new ContactPointAddress(ParentId = intermediateTwo.Id, Name = 'Child reparented');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    insert cpas;

    Map<Id, SObject> oldCpas = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, ParentId = intermediateOne.Id) };

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Account.Owner.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      User.SObjectType,
      oldCpas
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    System.assertEquals(false, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should not report false positive!');
    System.assertEquals(intermediateTwo.OwnerId, traversal.getOldLookupId(cpa, 'ParentId'));

    finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Account.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      oldCpas
    );
    traversal = finder.getParents(cpas);

    System.assertEquals(true, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should correctly report reparenting if ultimate lookup is different');
  }

  @IsTest
  static void shouldReportReparentingCorrectlyForNulls() {
    Account intermediateOne = [SELECT Id FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(ParentId = intermediateOne.Id, Name = 'Child reparented');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpa };
    insert cpas;

    Map<Id, SObject> oldOpps = new Map<Id, ContactPointAddress>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, ParentId = null) };

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      User.SObjectType,
      oldOpps
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    System.assertEquals(true, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should correctly report reparenting if old lookup null');

    oldOpps.put(cpa.Id, new ContactPointAddress(Id = cpa.Id, ParentId = intermediateOne.Id));
    cpa.ParentId = null;
    update cpa;

    finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Parent.Owner.Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      User.SObjectType,
      oldOpps
    );
    System.assertEquals(true, traversal.isUltimatelyReparented(cpa, 'ParentId'), 'Should correctly report reparenting if new lookup is null');
  }

  @IsTest
  static void shouldReportReparentingCorrectlyForImmediateParent() {
    Account parentOne = [SELECT Id FROM Account];
    Account parentTwo = new Account(Name = 'Parent2');
    insert parentTwo;

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'Child1');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = parentOne.Id, Name = 'Child2');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpaOne, cpaTwo };
    insert cpas;

    Map<Id, SObject> oldCpas = new Map<Id, SObject>{ cpaOne.Id => cpaOne, cpaTwo.Id => new ContactPointAddress(ParentId = parentTwo.Id) };
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      oldCpas
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    System.assertEquals(true, traversal.isUltimatelyReparented(cpaTwo, 'ParentId'));
    System.assertEquals(false, traversal.isUltimatelyReparented(cpaOne, 'ParentId'));
  }

  @IsTest
  static void shouldTrackMultipleParents() {
    Account parentOne = [SELECT Id FROM Account];

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'FirstParentedChild');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = parentOne.Id, Name = 'SecondParentedChild');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpaOne, cpaTwo };
    insert cpas;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(GrandparentRelationshipFieldPath__c = 'Name'),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    parentOne = (Account) RollupTestUtils.queryRecord(parentOne.Id);
    System.assertEquals(parentOne, traversal.retrieveParents(cpaOne.Id)[0], 'First opp parent should not be exluded!');
    System.assertEquals(parentOne, traversal.retrieveParents(cpaTwo.Id)[0], 'Second opp should not have been excluded!');
  }

  @IsTest
  static void shouldProperlyReturnParentRecordsWithNestedConditionals() {
    Account parentOne = new Account(Name = 'match', AccountNumber = '1');
    Account parentTwo = new Account(Name = 'non-match');
    Account parentThree = new Account(Name = 'another match');
    insert new List<Account>{ parentOne, parentTwo, parentThree };

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'FirstParentedChild');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = parentTwo.Id, Name = 'SecondParentedChild');
    ContactPointAddress cpaThree = new ContactPointAddress(ParentId = parentThree.Id, Name = 'ThirdParentedChild');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpaOne, cpaTwo, cpaThree };
    insert cpas;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        GrandparentRelationshipFieldPath__c = 'Parent.Name',
        CalcItemWhereClause__c = 'Parent.Name != \'\' AND (Parent.Name != \'' +
          parentOne.Name +
          '\' OR Parent.AccountNumber = \'' +
          parentOne.AccountNumber +
          '\' OR Parent.Name = \'' +
          parentThree.Name +
          '\') AND Parent.Name != \'' +
          parentTwo.Name +
          '\''
      ),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    // we don't anticipate it being necessary to return fields used in the where clause; just that records are filtered correctly
    Account expectedFirst = (Account) RollupTestUtils.queryRecord(parentOne.Id);
    parentThree = (Account) RollupTestUtils.queryRecord(parentThree.Id);
    System.assertEquals(expectedFirst, traversal.retrieveParents(cpaOne.Id)[0], 'First cpa parent should be returned, matches nested conditional!');
    System.assertEquals(null, traversal.retrieveParents(cpaTwo.Id), 'Second cpa parent should have been excluded with clause after nested conditional!');
    // parent three doesn't have additional fields (like AccountNumber), fine to use as is
    System.assertEquals(parentThree, traversal.retrieveParents(cpaThree.Id)[0], 'Third cpa parent should be returned, matches nested conditional');
  }

  @IsTest
  static void shouldTraverseAllTheWayUpWhenMetadataFlagIsEnabled() {
    Account parentOne = [SELECT Id FROM Account];
    Account parentTwo = new Account(Name = 'child parent', ParentId = parentOne.Id);
    // also start another chain of relationships
    Account secondParent = new Account(Name = 'second child parent', ParentId = parentOne.Id);
    insert new List<Account>{ parentTwo, secondParent };

    Account grandChild = new Account(Name = 'grandchild', ParentId = secondParent.Id);
    insert grandChild;

    Account greatGrandchild = new Account(Name = 'great-grandchild', ParentId = grandChild.Id);
    insert greatGrandchild;

    Account greatGreatGrandchild = new Account(Name = 'great great grandchild', ParentId = greatGrandchild.Id);
    insert greatGreatGrandchild;

    Account greatGreatGreatGrandchild = new Account(Name = 'great great great!', ParentId = greatGreatGrandchild.Id);
    insert greatGreatGreatGrandchild;

    ContactPointAddress cpaOne = new ContactPointAddress(ParentId = parentTwo.Id, Name = 'FirstParentedChild');
    ContactPointAddress cpaTwo = new ContactPointAddress(ParentId = greatGreatGreatGrandchild.Id, Name = 'Second parented child');
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ cpaOne, cpaTwo };
    insert cpas;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        RollupToUltimateParent__c = true,
        UltimateParentLookup__c = 'ParentId',
        GrandparentRelationshipFieldPath__c = 'Parent.Name',
        LookupFieldOnCalcItem__c = 'ParentId'
      ),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cpas);

    Account expectedAcc = (Account) RollupTestUtils.queryRecord(parentOne.Id);
    System.assertEquals(expectedAcc, traversal.retrieveParents(cpaOne.Id)[0], 'Ultimate parent should have been used!');
    System.assertEquals(expectedAcc, traversal.retrieveParents(cpaTwo.Id)[0], 'Ultimate parent should be found even if 5+ levels deep in hierarchy');
  }

  @IsTest
  static void shouldWorkWithHierarchiesWhereLookupFieldDiffersFromHierarchy() {
    Account hierarchyParent = [SELECT Id FROM Account];
    Account parent = new Account(Name = 'child parent', ParentId = hierarchyParent.Id);
    insert parent;

    Contact con = new Contact(LastName = 'hierarchy child', AccountId = parent.Id);
    List<Contact> cons = new List<Contact>{ con };
    insert cons;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(RollupToUltimateParent__c = true, UltimateParentLookup__c = 'ParentId', LookupFieldOnCalcItem__c = 'AccountId'),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(cons);
    Account expectedAcc = [SELECT Id FROM Account WHERE Id = :hierarchyParent.Id];
    Account retrievedAcc = (Account) traversal.retrieveParents(con.Id)[0];
    System.assertEquals(expectedAcc.Id, retrievedAcc.Id, 'Should correctly retrieve hierarchy');
  }

  @IsTest
  static void regressionTopLevelHierarchyDoesNotThrowException() {
    Account hierarchyParent = [SELECT Id, ParentId FROM Account];
    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(RollupToUltimateParent__c = true, UltimateParentLookup__c = 'ParentId', LookupFieldOnCalcItem__c = 'ParentId'),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Account>{ hierarchyParent });

    System.assertEquals(true, traversal.getIsFinished());
    System.assertEquals(true, traversal.getParentLookupToRecords().isEmpty());
  }

  @IsTest
  static void shouldSkipUltimateParentFieldInGrandparentFieldPathWhenHierarchyGrandparentRollup() {
    Account hierarchyParent = [SELECT Id, ParentId FROM Account];
    Contact hierarchyGrandchild = new Contact(LastName = 'Hierarchy grandchild', AccountId = hierarchyParent.Id);
    insert hierarchyGrandchild;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        RollupToUltimateParent__c = true,
        UltimateParentLookup__c = 'ParentId',
        LookupFieldOnCalcItem__c = 'AccountId',
        GrandparentRelationshipFieldPath__c = 'Account.Parent.Name'
      ),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Contact>{ hierarchyGrandchild });
    System.assertEquals(true, traversal.getIsFinished());
    Account retrievedAcc = (Account) traversal.retrieveParents(hierarchyGrandchild.Id)[0];
    System.assertEquals(hierarchyParent.Id, retrievedAcc.Id, 'Should correctly retrieve hierarchy');
  }

  @IsTest
  static void supportsJunctionObjectForIntermediateRelationship() {
    Account acc = [SELECT Id FROM Account];
    Individual firstParent = new Individual(LastName = 'One');
    Individual secondParent = new Individual(LastName = 'Two');
    insert new List<SObject>{ firstParent, secondParent };
    Contact firstChild = new Contact(AccountId = acc.Id, LastName = 'Child One', IndividualId = firstParent.Id);
    Contact secondChild = new Contact(AccountId = acc.Id, LastName = 'Child Two', IndividualId = secondParent.Id);
    insert new List<SObject>{ firstChild, secondChild };

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        LookupFieldOnCalcItem__c = 'Id', // should not matter in this context
        GrandparentRelationshipFieldPath__c = 'Contacts.Individual.Name',
        OneToManyGrandparentFields__c = 'Contact.AccountId'
      ),
      uniqueFieldNames,
      uniqueFieldNames,
      Individual.SObjectType,
      new Map<Id, SObject>()
    );
    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Account>{ acc });

    System.assertEquals(true, traversal.getIsFinished());
    List<SObject> returnedParents = traversal.retrieveParents(acc.Id);
    System.assertEquals(2, returnedParents?.size(), 'Should have retrieved both individuals related to account');
    Boolean foundFirstParent = false;
    Boolean foundSecondParent = false;
    for (SObject parent : returnedParents) {
      if (parent.Id == firstParent.Id) {
        foundFirstParent = true;
      } else if (parent.Id == secondParent.Id) {
        foundSecondParent = true;
      }
    }
    System.assertEquals(true, foundFirstParent);
    System.assertEquals(true, foundSecondParent);
  }

  @IsTest
  static void properlyRetrievesCurrencyIsoCodeForUltimateParents() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }

    Account hierarchyParent = [SELECT Id, ParentId FROM Account];
    Account hierarchyGrandparent = new Account(Name = 'Hierarchy grandparent');
    insert hierarchyGrandparent;
    hierarchyParent.ParentId = hierarchyGrandparent.Id;
    update hierarchyParent;
    Contact hierarchyGrandchild = new Contact(LastName = 'Hierarchy grandchild', AccountId = hierarchyParent.Id);
    insert hierarchyGrandchild;

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        RollupToUltimateParent__c = true,
        UltimateParentLookup__c = 'ParentId',
        LookupFieldOnCalcItem__c = 'AccountId',
        GrandparentRelationshipFieldPath__c = 'Account.Parent.Name'
      ),
      uniqueFieldNames,
      uniqueFieldNames,
      Account.SObjectType,
      new Map<Id, SObject>()
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Contact>{ hierarchyGrandchild });
    System.assertEquals(true, traversal.getIsFinished());
    SObject retrievedAcc = traversal.retrieveParents(hierarchyGrandchild.Id)[0];
    System.assertEquals(hierarchyGrandparent.Id, retrievedAcc.Id, 'Should correctly retrieve hierarchy');
    System.assertEquals(true, retrievedAcc.isSet(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME));
    // just to be SUPER safe
    hierarchyGrandparent = (Account) RollupTestUtils.queryRecord(hierarchyGrandparent.Id);
    System.assertNotEquals(null, hierarchyGrandparent.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME));
    System.assertEquals(
      hierarchyGrandparent.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME),
      retrievedAcc.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME)
    );
  }

  @IsTest
  static void fullRecordSetProperlyRetrievesAllGrandchildren() {
    Account acc = [SELECT OwnerId FROM Account];
    Account secondAccount = new Account(Name = 'Second Parent', OwnerId = acc.OwnerId);
    insert secondAccount;

    Opportunity opp = new Opportunity(Name = 'Does match', AccountId = acc.Id, CloseDate = System.today(), StageName = 'One');
    Opportunity secondOpp = new Opportunity(Name = 'Does match', AccountId = secondAccount.Id, CloseDate = System.today(), StageName = 'Two');
    insert new List<Opportunity>{ opp, secondOpp };

    RollupRelationshipFieldFinder finder = new RollupRelationshipFieldFinder(
      control,
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'PasswordResetAttempt',
        RollupOperation__c = 'COUNT_DISTINCT',
        GrandparentRelationshipFieldPath__c = 'Account.Owner.PasswordResetAttempt',
        CalcItemWhereClause__c = 'Name = \'' + opp.Name + '\'',
        IsFullRecordSet__c = true
      ),
      new Set<String>{ 'Name' },
      uniqueFieldNames,
      User.SObjectType,
      new Map<Id, SObject>{ opp.Id => new Opportunity(AccountId = acc.Id, Name = 'Does not match', Id = opp.Id) }
    );

    RollupRelationshipFieldFinder.Traversal traversal = finder.getParents(new List<Opportunity>{ opp });
    System.assertEquals(true, traversal.getIsFinished());
    Map<String, Rollup.CalcItemBag> lookupToCalcItems = traversal.getParentLookupToRecords();
    System.assertEquals(2, lookupToCalcItems.get(acc.OwnerId).getAll().size(), lookupToCalcItems);
  }

  @IsTest
  static void correctlyReferencesOneToManyAdjacentRecords() {
    Account acc = [SELECT Id FROM Account];
    Account secondAccount = new Account(Name = 'Two', AnnualRevenue = 50);
    Individual firstParent = new Individual(LastName = 'One');
    insert new List<SObject>{ firstParent, secondAccount };
    Contact firstChild = new Contact(AccountId = acc.Id, LastName = 'Child One', IndividualId = firstParent.Id);
    Contact secondChild = new Contact(AccountId = secondAccount.Id, LastName = 'Child Two', IndividualId = firstParent.Id);
    insert new List<SObject>{ firstChild, secondChild };

    RollupRelationshipFieldFinder.Traversal traversal = new RollupRelationshipFieldFinder(
        control,
        new Rollup__mdt(
          RollupFieldOnCalcItem__c = 'AnnualRevenue',
          LookupFieldOnCalcItem__c = 'Id',
          GrandparentRelationshipFieldPath__c = 'Contacts.Individual.Name',
          OneToManyGrandparentFields__c = 'Contact.AccountId',
          LookupFieldOnLookupObject__c = 'Id'
        ),
        uniqueFieldNames,
        uniqueFieldNames,
        Individual.SObjectType,
        new Map<Id, SObject>()
      )
      .getParents(new List<Account>{ acc });

    System.assertEquals(true, traversal.getIsFinished());
    Boolean hasBothAccounts = false;
    for (SObject calcItem : traversal.getParentLookupToRecords().get('' + firstParent.Id).getAll()) {
      if (calcItem.Id == secondAccount.Id) {
        System.assertEquals(secondAccount.AnnualRevenue, calcItem.get(Account.AnnualRevenue));
        hasBothAccounts = true;
        break;
      }
    }
    System.assertEquals(true, hasBothAccounts, traversal.getParentLookupToRecords());
  }
}
