{
  writeShellApplication,
  wireguard-tools,
  iptables,

  netns ? "hydrus",
  wgDefault ? "192.168.2.1",
  wgService ? "192.168.2.2",
}:
writeShellApplication {
  name = "hydrus-testutil-start-wireguard-tunnel";
  runtimeInputs = [
    wireguard-tools
    iptables
  ];
  text = ''
    # This is a quick'n'dirty Wireguard setup. This is not the easiest way to
    # route traffic between namespaces, but it demonstrates how to set up
    # Wireguard tunneling. In most cases, the two interfaces would be on
    # different machines, rather than just separate namespaces.

    wg genkey > /tmp/privatekey
    wg pubkey < /tmp/privatekey > /tmp/publickey
    wg genkey > /tmp/hyprivatekey
    wg pubkey < /tmp/hyprivatekey > /tmp/hypublickey

    ip link add dev wg0 type wireguard
    ip address add dev wg0 ${wgDefault} peer ${wgService}
    wg set wg0 listen-port 51820 private-key /tmp/privatekey peer "$(cat /tmp/hypublickey)" allowed-ips 0.0.0.0/0
    ip link set up dev wg0

    ip link add dev wg1 type wireguard
    ip link set wg1 netns ${netns}
    ip netns exec ${netns} wg set wg1 listen-port 51821 private-key /tmp/hyprivatekey peer "$(cat /tmp/publickey)" allowed-ips 0.0.0.0/0 endpoint 127.0.0.1:51820
    ip -n ${netns} address add dev wg1 ${wgService} peer ${wgDefault}
    ip -n ${netns} link set up dev wg1
    ip -n ${netns} route add default dev wg1

    iptables -t nat -A POSTROUTING -s ${wgService}/32 -o eth0 -j MASQUERADE
    iptables -A FORWARD -i wg0 -j ACCEPT
    iptables -A FORWARD -o wg0 -j ACCEPT
  '';
}
