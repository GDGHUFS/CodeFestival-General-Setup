#!/bin/bash
# 필요시 수정 및 추가:
# /etc/hosts에 도메인 넣고 /etc/nftables/main.nft의 allowed_dst_ipv4 IP 주소 넣으면 됨.
echo "DNS에 도메인 목록을 추가하겠습니다."
echo "203.253.71.13 ps.gdghufs.com" | sudo tee --append /etc/hosts

echo "IP 허용 목록을 설정하겠습니다."
sudo mv /etc/nftables/main.nft /backup.nft
sudo tee -a /etc/nftables/main.nft << 'EOF'
flush ruleset

table inet nftables_svc {

        # protocols to allow
        set allowed_protocols {
                type inet_proto
                elements = { icmp, icmpv6 }
        }
        # interfaces to accept any traffic on
        set allowed_interfaces {
                type ifname
                elements = { "lo" }
        }

        # services to allow
        set allowed_tcp_dports {
                type inet_service
                elements = { ssh, 9090 }
        }

        # 외부로 나가는 트래픽에서 허용할 목적지 IP 목록
        set allowed_dst_ipv4 {
                type ipv4_addr
                elements = {
                        203.253.71.13
                }
        }

        set allowed_dst_ipv6 {
                type ipv6_addr
                elements = {
                        ::1
                }
        }

        # this chain gathers all accept conditions
        chain allow {
                ct state established,related accept

                meta l4proto @allowed_protocols accept
                iifname @allowed_interfaces accept
                tcp dport @allowed_tcp_dports accept
        }

        # base-chain for traffic to this host
        chain INPUT {
                type filter hook input priority filter + 20
                policy accept

                jump allow
                reject with icmpx type port-unreachable
        }

        # 외부로 나가는 트래픽 제어
        chain OUTPUT {
                type filter hook output priority filter + 20
                policy drop

                # 이미 열린 연결(응답 트래픽)은 허용
                ct state established,related accept

                # 루프백 인터페이스는 항상 허용
                oifname @allowed_interfaces accept

                # root(UID 0)는 제한 없이 허용
                meta skuid 0 accept

                # 비root 사용자의 외부 접속: 지정된 IP만 허용
                ip daddr @allowed_dst_ipv4 accept
                ip6 daddr @allowed_dst_ipv6 accept

                # 나머지는 전부 drop
        }
}
EOF

sudo nft -f /etc/nftables/main.nft