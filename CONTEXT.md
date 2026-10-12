# SwiftStash

A Swift caching library: an actor-isolated cache whose entries are kept in memory and persisted through a pluggable storage engine.

## Language

### Caching

**Cache**:
The actor that holds entries, applies an eviction policy, and persists changes through its storage engine.

**Cache Key**:
The value identifying an entry in a cache, with a lossless string form used by persistent storage. A bare "key" always means the cache key.
_Avoid_: Identifier, ID

**Entry**:
A cached value together with its metadata.
_Avoid_: Item, record, element

**Entry Metadata**:
Everything about an entry except its value: cache key, creation date, last-access date, access count, expiration date, and cost.
_Avoid_: Attributes, info

**Eviction Policy**:
The order in which entries are removed when the cache shrinks, and the age at which entries expire.

### Persistence

**Storage Engine**:
The component a cache loads entries from and persists entries to, such as memory or disk.
_Avoid_: Backend, store, persistence layer

**Serializer**:
The component converting a value to and from the bytes the disk storage engine writes.
_Avoid_: Encoder, coder, transformer

**Entry File**:
The file holding one entry on disk: its entry header followed by its serialized value.

**Entry Header**:
The part of an entry file holding the entry metadata, updatable without rewriting the value.

### Encryption

**Encryption Key**:
The secret that encrypts entry files and makes their filenames unguessable. Always called "encryption key", never a bare "key", which means the cache key.
_Avoid_: Key, secret, password
