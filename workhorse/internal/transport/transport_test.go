package transport

import (
	"net"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewDefaultTransport(t *testing.T) {
	require.IsType(t, &DefaultTransport{}, NewDefaultTransport())
}

func TestValidateIpAddress(t *testing.T) {
	// Save the original lookup IP function to restore later
	originalLookupIP := lookupIPFunc
	defer func() { lookupIPFunc = originalLookupIP }()

	lookupIPFunc = func(_ string) ([]net.IP, error) {
		return []net.IP{net.ParseIP("192.0.2.1")}, nil
	}

	tests := []struct {
		name             string
		address          string
		allowedEndpoints []string
		allowLocal       bool
		errorMessage     string
	}{
		{
			name:             "Public IP Address",
			address:          "93.184.215.14:80",
			allowedEndpoints: nil,
			allowLocal:       false,
		},
		{
			name:             "Private IP Address",
			address:          "192.168.0.0:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 192.168.0.0 is not allowed: private IPs are not allowed",
		},
		{
			name:             "Private IP Address",
			address:          "172.16.0.0:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 172.16.0.0 is not allowed: private IPs are not allowed",
		},
		{
			name:             "Private IP Address with allowed endpoint in URL format",
			address:          "172.16.123.1:9000",
			allowedEndpoints: []string{"http://172.16.123.1:9000"},
			allowLocal:       false,
		},
		{
			name:             "Private IP Address with allowed endpoint in host:port format",
			address:          "172.16.123.1:9000",
			allowedEndpoints: []string{"172.16.123.1:9000"},
			allowLocal:       false,
		},
		{
			name:             "Private IP Address with allowed endpoint as IP address",
			address:          "172.16.123.1:9000",
			allowedEndpoints: []string{"172.16.123.1"},
			allowLocal:       false,
		},
		{
			name:             "Private IP Address with allowed endpoint as IP network range",
			address:          "10.12.24.1:9000",
			allowedEndpoints: []string{"10.12.24.0/23"},
			allowLocal:       false,
		},
		{
			name:             "Private IP Address with non matching IP network range",
			address:          "10.13.24.1:9000",
			allowedEndpoints: []string{"10.12.24.0/23"},
			allowLocal:       false,
			errorMessage:     "IP 10.13.24.1 is not allowed: private IPs are not allowed",
		},
		{
			name:             "Private IP Address with allowed endpoint as host",
			address:          "192.0.2.1:9000",
			allowedEndpoints: []string{"example.com"},
			allowLocal:       false,
		},
		{
			name:             "Private IPv6 Address",
			address:          "[fd00::1]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP fd00::1 is not allowed: private IPs are not allowed",
		},
		{
			name:             "Loopback IP Address",
			address:          "127.0.0.1:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 127.0.0.1 is not allowed: loopback IPs are not allowed",
		},
		{
			name:             "Loopback IP Address with Allow Localhost",
			address:          "127.0.0.1:80",
			allowedEndpoints: nil,
			allowLocal:       true,
		},
		{
			name:             "Loopback IPv6 Address",
			address:          "[0000:0000:0000:0000:0000:0000:0000:0001]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP ::1 is not allowed: loopback IPs are not allowed",
		},
		{
			name:             "Loopback IPv6 Address",
			address:          "[::1]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP ::1 is not allowed: loopback IPs are not allowed",
		},
		{
			name:             "Localhost IP Address",
			address:          "0.0.0.0:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 0.0.0.0 is not allowed: unspecified IPs are not allowed",
		},
		{
			name:             "Localhost IP Address with Allow Localhost",
			address:          "0.0.0.0:80",
			allowedEndpoints: nil,
			allowLocal:       true,
		},
		{
			name:             "Link-Local Multicast IP Address",
			address:          "224.0.0.0:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 224.0.0.0 is not allowed: link-local unicast and multicast IPs are not allowed",
		},
		{
			name:             "Link-Local Unicast IP Address",
			address:          "169.254.0.0:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 169.254.0.0 is not allowed: link-local unicast and multicast IPs are not allowed",
		},
		{
			name:             "Broadcast IP Address",
			address:          "255.255.255.255:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 255.255.255.255 is not allowed: limited broadcast IPs are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address (AWS/GCP/Azure)",
			address:          "169.254.169.254:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 169.254.169.254 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address (Alibaba)",
			address:          "100.100.100.200:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 100.100.100.200 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address (OCI)",
			address:          "192.0.0.192:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 192.0.0.192 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address (AWS IPv6)",
			address:          "[fd00:ec2::254]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP fd00:ec2::254 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata Zone-Qualified IP Address (AWS IPv6)",
			address:          "[fd00:ec2::254%0]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP fd00:ec2::254 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IPv4-Mapped IPv6 Address (AWS/GCP/Azure)",
			address:          "[0:0:0:0:0:ffff:a9fe:a9fe]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 169.254.169.254 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IPv4-Mapped IPv6 Address (Alibaba)",
			address:          "[0:0:0:0:0:ffff:6464:64c8]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 100.100.100.200 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IPv4-Mapped IPv6 Address (OCI)",
			address:          "[0:0:0:0:0:ffff:c000:c0]:80",
			allowedEndpoints: nil,
			allowLocal:       false,
			errorMessage:     "IP 192.0.0.192 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address with allowed endpoint (not bypassable)",
			address:          "169.254.169.254:80",
			allowedEndpoints: []string{"169.254.169.254"},
			allowLocal:       false,
			errorMessage:     "IP 169.254.169.254 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address with allowed endpoint in URL format (not bypassable)",
			address:          "100.100.100.200:80",
			allowedEndpoints: []string{"http://100.100.100.200"},
			allowLocal:       false,
			errorMessage:     "IP 100.100.100.200 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address with allowed endpoint as IP network range (not bypassable)",
			address:          "192.0.0.192:80",
			allowedEndpoints: []string{"192.0.0.192/32"},
			allowLocal:       false,
			errorMessage:     "IP 192.0.0.192 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata IP Address within allowed network range (not bypassable)",
			address:          "100.100.100.200:80",
			allowedEndpoints: []string{"100.64.0.0/10"},
			allowLocal:       false,
			errorMessage:     "IP 100.100.100.200 is not allowed: cloud metadata endpoints are not allowed",
		},
		{
			name:             "Cloud Metadata Neighbor within allowed network range",
			address:          "100.100.100.201:80",
			allowedEndpoints: []string{"100.64.0.0/10"},
			allowLocal:       false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			err := validateIPAddress(tc.allowLocal, tc.allowedEndpoints)("", tc.address, nil)
			if tc.errorMessage != "" {
				require.EqualError(t, err, tc.errorMessage)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestValidateIpAddressMetadataNotBypassedByAllowlistedDomain(t *testing.T) {
	// Save the original lookup IP function to restore later
	originalLookupIP := lookupIPFunc
	defer func() { lookupIPFunc = originalLookupIP }()

	// The admin allowlists a domain whose DNS (controlled by the admin)
	// resolves to a cloud metadata endpoint.
	lookupIPFunc = func(hostname string) ([]net.IP, error) {
		if hostname == "metadata-proxy.internal" {
			return []net.IP{net.ParseIP("169.254.169.254")}, nil
		}

		return []net.IP{net.ParseIP("192.0.2.1")}, nil
	}

	err := validateIPAddress(false, []string{"metadata-proxy.internal"})("", "169.254.169.254:80", nil)
	require.EqualError(t, err, "IP 169.254.169.254 is not allowed: cloud metadata endpoints are not allowed")
}

func TestParseCIDR(t *testing.T) {
	network := parseCIDR("192.168.0.0/24")
	require.True(t, network.Contains(net.ParseIP("192.168.0.0")))
}

func TestParseCIDRPanic(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic")
		}
	}()
	parseCIDR("192.168")
}
