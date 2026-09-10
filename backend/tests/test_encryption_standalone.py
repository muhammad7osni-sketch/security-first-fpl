"""
PHASE 4: Standalone encryption tests (no external dependencies)
Tests AES-256-GCM without network calls or external services
"""

import sys
import os

# Add app to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

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
    print(f"✓ PASS: Encrypted token: {encrypted[:50]}...")


def test_encrypt_with_associated_data(encryption_service):
    """Test encryption with associated data (AD)."""
    plaintext = "test-token"
    ad = "user-id-123"

    encrypted = encryption_service.encrypt(plaintext, associated_data=ad)
    assert encrypted is not None
    assert encrypted.startswith("kv_1_")
    print(f"✓ PASS: Encrypted with AD: {encrypted[:50]}...")


def test_encrypt_empty_plaintext(encryption_service):
    """Test encryption of empty plaintext."""
    encrypted = encryption_service.encrypt("")
    assert encrypted == ""
    print("✓ PASS: Empty plaintext returns empty string")


def test_decrypt_valid_ciphertext(encryption_service):
    """Test decryption of valid ciphertext."""
    plaintext = "test-refresh-token-12345"
    encrypted = encryption_service.encrypt(plaintext)

    decrypted = encryption_service.decrypt(encrypted)
    assert decrypted == plaintext
    print(f"✓ PASS: Decrypted plaintext: {decrypted}")


def test_decrypt_with_associated_data(encryption_service):
    """Test decryption with associated data."""
    plaintext = "test-token"
    ad = "user-id-123"

    encrypted = encryption_service.encrypt(plaintext, associated_data=ad)
    decrypted = encryption_service.decrypt(encrypted, associated_data=ad)

    assert decrypted == plaintext
    print(f"✓ PASS: Decrypted with AD: {decrypted}")


def test_decrypt_with_wrong_associated_data(encryption_service):
    """Test decryption with wrong associated data (should fail)."""
    plaintext = "test-token"
    ad = "user-id-123"

    encrypted = encryption_service.encrypt(plaintext, associated_data=ad)
    decrypted = encryption_service.decrypt(encrypted, associated_data="wrong-ad")

    assert decrypted is None  # AD verification failed
    print("✓ PASS: Wrong AD detected (decryption fails)")


def test_decrypt_empty_ciphertext(encryption_service):
    """Test decryption of empty ciphertext."""
    decrypted = encryption_service.decrypt("")
    assert decrypted is None
    print("✓ PASS: Empty ciphertext returns None")


def test_decrypt_invalid_version(encryption_service):
    """Test decryption with invalid version prefix."""
    decrypted = encryption_service.decrypt("invalid_prefix_abc123")
    assert decrypted is None
    print("✓ PASS: Invalid version rejected")


def test_decrypt_tampered_ciphertext(encryption_service):
    """Test decryption of tampered ciphertext (should fail)."""
    plaintext = "test-token"
    encrypted = encryption_service.encrypt(plaintext)

    # Tamper with ciphertext
    parts = encrypted.split("_", 1)
    ciphertext_b64 = parts[1]
    # Flip a bit in the ciphertext
    tampered_bytes = bytearray(base64.b64decode(ciphertext_b64))
    if len(tampered_bytes) > 0:
        tampered_bytes[0] ^= 0xFF  # Flip all bits in first byte
    tampered_ciphertext = "kv_1_" + base64.b64encode(tampered_bytes).decode("utf-8")

    decrypted = encryption_service.decrypt(tampered_ciphertext)
    assert decrypted is None  # Authentication tag verification should fail
    print("✓ PASS: Tampered ciphertext detected (GCM tag verification failed)")


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
        print(f"✓ PASS: Round-trip success: {plaintext} → encrypted → decrypted")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
