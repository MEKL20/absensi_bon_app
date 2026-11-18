"""Validate public mobile build configuration without printing its value."""
import os
from urllib.parse import urlsplit


def validate_api_url(value):
    parsed = urlsplit(value)
    if (not value or value != value.strip() or parsed.scheme != 'https'
            or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or any(c.isspace() for c in value)):
        raise ValueError('Set repository variable API_BASE_URL to an HTTPS API base URL without credentials, query or fragment.')
    return value


if __name__ == '__main__':
    validate_api_url(os.environ.get('API_BASE_URL', ''))
    print('Mobile API configuration validated.')
