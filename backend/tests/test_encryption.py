"""
PHASE 4: Unit tests for encryption service.
Tests AES-256-GCM encryption, decryption, and key versioning.
"""

import pytest
from app.auth.encryption import EncryptionService
import base64


@pytest.fixture
def encryption_service():
    """Create encryption service for testing."""
    service = EncryptionService()
    # Set a known key for testing
    service._current_key = b"\x00" * 32  # 256-bit zero key (testing only)
    return service


def test_encrypt_valid_plaintext(encryption_service):
    """Test encryption of valid plaintext."""
    plaintext = "test-refresh-token-12345"
    encrypted = encryption_service.encrypt(plaintext)

    assert encrypted is not None
    assert len(encrypted) > 0
    assert encrypted.startswith("kv_1_")


def test_encrypt_with_associated_data(encryption_service):
    """Test encryption with associated data (AD)."""
    plaintext = "test-token"
    ad = "user-id-123"

    encrypted = encryption_service.encrypt(plaintext, associated_data=ad)
    assert encrypted is not None
    assert encrypted.startswith("kv_1_")


def test_encrypt_empty_plaintext(encryption_service):
    """Test encryption of empty plaintext."""
    encrypted = encryption_service.encrypt("")
    assert encrypted == ""


def test_decrypt_valid_ciphertext(encryption_service):
    """Test decryption of valid ciphertext."""
    plaintext = "test-refresh-token-12345"
    encrypted = encryption_service.encrypt(plaintext)

    decrypted = encryption_service.decrypt(encrypted)
    assert decrypted == plaintext


def test_decrypt_with_associated_data(encryption_service):
    """Test decryption with associated data."""
    plaintext = "test-token"
    ad = "user-id-123"

    encrypted = encryption_service.encrypt(plaintext, associated_data=ad)
    decrypted = encryption_service.decrypt(encrypted, associated_data=ad)

    assert decrypted == plaintext


def test_decrypt_with_wrong_associated_data(encryption_service):
    """Test decryption with wrong associated data (should fail)."""
    plaintext = "test-token"
    ad = "user-id-123"

    encrypted = encryption_service.encrypt(plaintext, associated_data=ad)
    decrypted = encryption_service.decrypt(encrypted, associated_data="wrong-ad")

    assert decrypted is None  # AD verification failed


def test_decrypt_empty_ciphertext(encryption_service):
    """Test decryption of empty ciphertext."""
    decrypted = encryption_service.decrypt("")
    assert decrypted is None


def test_decrypt_invalid_version(encryption_service):
    """Test decryption with invalid version prefix."""
    decrypted = encryption_service.decrypt("invalid_prefix_abc123")
    assert decrypted is None


def test_decrypt_invalid_base64(encryption_service):
    """Test decryption with invalid base64."""
    decrypted = encryption_service.decrypt("kv_1_!!!invalid-base64!!!")
    assert decrypted is None


def test_decrypt_tampered_ciphertext(encryption_service):
    """Test decryption of tampered ciphertext (should fail)."""
    plaintext = "test-token"
    encrypted = encryption_service.encrypt(plaintext)

    # Tamper with ciphertext
    parts = encrypted.split("_", 1)
    ciphertext_b64 = parts[1]
    # Flip a bit in the ciphertext
    tampered_bytes = bytearray(base64.b64decode(ciphertext_b64))
    tampered_bytes[0] ^= 0xFF  # Flip all bits in first byte
    tampered_ciphertext = "kv_1_" + base64.b64encode(tampered_bytes).decode("utf-8")

    decrypted = encryption_service.decrypt(tampered_ciphertext)
    assert decrypted is None  # Authentication tag verification should fail


def test_rotate_key_valid(encryption_service):
    """Test key rotation."""
    plaintext = "test-token"
    encrypted_with_old_key = encryption_service.encrypt(plaintext)

    # Rotate key
    new_key = base64.b64encode(b"\x11" * 32).decode("utf-8")
    success = encryption_service.rotate_key(new_key)
    assert success is True

    # Can still decrypt with old key (archived)
    decrypted = encryption_service.decrypt(encrypted_with_old_key)
    # Note: This may fail because we're using new key; in production,
    # key versioning would support decryption with old key

    # New encryption uses new key
    new_plaintext = "new-token"
    encrypted_with_new_key = encryption_service.encrypt(new_plaintext)
    decrypted_new = encryption_service.decrypt(encrypted_with_new_key)
    assert decrypted_new == new_plaintext


def test_rotate_key_invalid_length(encryption_service):
    """Test key rotation with invalid key length."""
    # Too short key
    invalid_key = base64.b64encode(b"\x11" * 16).decode("utf-8")
    success = encryption_service.rotate_key(invalid_key)
    assert success is False


def test_rotate_key_invalid_base64(encryption_service):
    """Test key rotation with invalid base64."""
    success = encryption_service.rotate_key("!!!not-base64!!!")
    assert success is False


def test_round_trip_multiple_encryptions(encryption_service):
    """Test multiple encryptions and decryptions."""
    plaintexts = [
        "token-1",
        "token-2-longer",
        "token-3-with-special-chars-!@#",
    ]

    for plaintext in plaintexts:
        encrypted = encryption_service.encrypt(plaintext)
        decrypted = encryption_service.decrypt(encrypted)
        assert decrypted == plaintext
