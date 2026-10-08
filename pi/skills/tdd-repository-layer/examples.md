# Repository Layer Examples

## Complete Repository Interface

```java
@Repository
public interface FirmRepository extends JpaRepository<Firm, Integer> {

    Optional<Firm> findBySubdomain(String subdomain);

    List<Firm> findByActive(Boolean active);

    List<Firm> findByFirmIdOrderByCreatedAtDesc(Integer firmId);

    Page<Firm> findByActive(Boolean active, Pageable pageable);

    long countByFirmId(Integer firmId);

    boolean existsByEmail(String email);

    void deleteByFirmId(Integer firmId);
}
```

## Pagination

```java
// Repository method
Page<Firm> findByActive(Boolean active, Pageable pageable);
```

```groovy
// Test
void "supports pagination"() {
    given: "multiple firms"
    (1..25).each { i ->
        repository.save(new Firm(name: "Firm $i", subdomain: "firm-$i-${UUID.randomUUID().toString().substring(0,8)}"))
    }

    when: "querying first page"
    def page = repository.findByActive(true, Pageable.from(0, 10, Sort.of(Sort.Order.asc("name"))))

    then:
    page.content.size() == 10
    page.totalSize >= 25
    page.totalPages >= 3
    page.hasNext()
}
```

## Custom @Query

```java
@Query("SELECT f FROM Firm f WHERE f.active = true AND f.createdAt > :cutoff")
List<Firm> findRecentActiveFirms(LocalDateTime cutoff);

@Query(value = "SELECT * FROM private.firm WHERE metadata @> :json::jsonb", nativeQuery = true)
List<Firm> findByJsonbContains(String json);
```

## Relationship Testing

```groovy
void "finds inbox items by firm ID"() {
    given: "a firm exists"
    def firm = new Firm(name: "Test Firm", subdomain: "test-${UUID.randomUUID().toString().substring(0,8)}")
    firm.encryptionKeyId = UUID.randomUUID()
    def savedFirm = firmRepository.save(firm)

    and: "inbox items belong to that firm"
    def item1 = new EmailInboxItem(firmId: savedFirm.id, emailId: "email1")
    def item2 = new EmailInboxItem(firmId: savedFirm.id, emailId: "email2")
    inboxRepository.saveAll([item1, item2])

    when:
    def results = inboxRepository.findByFirmId(savedFirm.id)

    then:
    results.size() == 2
    results.every { it.firmId == savedFirm.id }
}
```

## FK Constraint Testing

```groovy
void "enforces foreign key constraint"() {
    given: "inbox item with non-existent firm ID"
    def item = new EmailInboxItem(firmId: 99999, emailId: "test")

    when:
    inboxRepository.save(item)

    then:
    thrown(Exception)
}
```

## Batch Operations

```java
List<Entity> entities = List.of(entity1, entity2, entity3);
repository.saveAll(entities);   // single transaction
repository.deleteAll(entities);
```

## Optional Return Type Testing

```groovy
void "handles missing entity"() {
    when:
    def result = repository.findBySubdomain("does-not-exist")

    then:
    !result.present
}

void "unwraps present Optional"() {
    given:
    def saved = repository.save(new Firm(name: "Test", subdomain: "test-${UUID.randomUUID().toString().substring(0,8)}"))

    when:
    def result = repository.findById(saved.id)

    then:
    result.present
    result.get().id == saved.id
}
```
