// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package bindings

import (
	"encoding/json"

	"github.com/ethereum-optimism/optimism/op-bindings/solc"
)

const KromaMintableERC20StorageLayoutJSON = "{\"storage\":[{\"astId\":1000,\"contract\":\"contracts/universal/KromaMintableERC20.sol:KromaMintableERC20\",\"label\":\"_balances\",\"offset\":0,\"slot\":\"0\",\"type\":\"t_mapping(t_address,t_uint256)\"},{\"astId\":1001,\"contract\":\"contracts/universal/KromaMintableERC20.sol:KromaMintableERC20\",\"label\":\"_allowances\",\"offset\":0,\"slot\":\"1\",\"type\":\"t_mapping(t_address,t_mapping(t_address,t_uint256))\"},{\"astId\":1002,\"contract\":\"contracts/universal/KromaMintableERC20.sol:KromaMintableERC20\",\"label\":\"_totalSupply\",\"offset\":0,\"slot\":\"2\",\"type\":\"t_uint256\"},{\"astId\":1003,\"contract\":\"contracts/universal/KromaMintableERC20.sol:KromaMintableERC20\",\"label\":\"_name\",\"offset\":0,\"slot\":\"3\",\"type\":\"t_string_storage\"},{\"astId\":1004,\"contract\":\"contracts/universal/KromaMintableERC20.sol:KromaMintableERC20\",\"label\":\"_symbol\",\"offset\":0,\"slot\":\"4\",\"type\":\"t_string_storage\"}],\"types\":{\"t_address\":{\"encoding\":\"inplace\",\"label\":\"address\",\"numberOfBytes\":\"20\"},\"t_mapping(t_address,t_mapping(t_address,t_uint256))\":{\"encoding\":\"mapping\",\"label\":\"mapping(address =\u003e mapping(address =\u003e uint256))\",\"numberOfBytes\":\"32\",\"key\":\"t_address\",\"value\":\"t_mapping(t_address,t_uint256)\"},\"t_mapping(t_address,t_uint256)\":{\"encoding\":\"mapping\",\"label\":\"mapping(address =\u003e uint256)\",\"numberOfBytes\":\"32\",\"key\":\"t_address\",\"value\":\"t_uint256\"},\"t_string_storage\":{\"encoding\":\"bytes\",\"label\":\"string\",\"numberOfBytes\":\"32\"},\"t_uint256\":{\"encoding\":\"inplace\",\"label\":\"uint256\",\"numberOfBytes\":\"32\"}}}"

var KromaMintableERC20StorageLayout = new(solc.StorageLayout)

var KromaMintableERC20DeployedBin = "0x608060405234801561001057600080fd5b506004361061011b5760003560e01c806340c10f19116100b25780639dc29fac11610081578063a9059cbb11610066578063a9059cbb14610284578063dd62ed3e14610297578063ee9a31a2146102dd57600080fd5b80639dc29fac1461025e578063a457c2d71461027157600080fd5b806340c10f191461020357806354fd4d501461021857806370a082311461022057806395d89b411461025657600080fd5b806318160ddd116100ee57806318160ddd146101bc57806323b872dd146101ce578063313ce567146101e157806339509351146101f057600080fd5b806301ffc9a714610120578063033964be1461014857806306fdde0314610194578063095ea7b3146101a9575b600080fd5b61013361012e3660046110a0565b610304565b60405190151581526020015b60405180910390f35b61016f7f000000000000000000000000000000000000000000000000000000000000000081565b60405173ffffffffffffffffffffffffffffffffffffffff909116815260200161013f565b61019c6103a4565b60405161013f9190611115565b6101336101b736600461118f565b610436565b6002545b60405190815260200161013f565b6101336101dc3660046111b9565b61044e565b6040516012815260200161013f565b6101336101fe36600461118f565b610472565b61021661021136600461118f565b6104be565b005b61019c6105cc565b6101c061022e3660046111f5565b73ffffffffffffffffffffffffffffffffffffffff1660009081526020819052604090205490565b61019c61066f565b61021661026c36600461118f565b61067e565b61013361027f36600461118f565b61077b565b61013361029236600461118f565b610832565b6101c06102a5366004611210565b73ffffffffffffffffffffffffffffffffffffffff918216600090815260016020908152604080832093909416825291909152205490565b61016f7f000000000000000000000000000000000000000000000000000000000000000081565b60007f01ffc9a7000000000000000000000000000000000000000000000000000000007f30a0c5a9000000000000000000000000000000000000000000000000000000007fffffffff00000000000000000000000000000000000000000000000000000000841682148061039c57507fffffffff00000000000000000000000000000000000000000000000000000000848116908216145b949350505050565b6060600380546103b390611243565b80601f01602080910402602001604051908101604052809291908181526020018280546103df90611243565b801561042c5780601f106104015761010080835404028352916020019161042c565b820191906000526020600020905b81548152906001019060200180831161040f57829003601f168201915b5050505050905090565b600033610444818585610840565b5060019392505050565b60003361045c8582856109c0565b610467858585610a7d565b506001949350505050565b33600081815260016020908152604080832073ffffffffffffffffffffffffffffffffffffffff8716845290915281205490919061044490829086906104b9908790611296565b610840565b3373ffffffffffffffffffffffffffffffffffffffff7f0000000000000000000000000000000000000000000000000000000000000000161461056e5760405162461bcd60e51b815260206004820152603160248201527f4b726f6d614d696e7461626c6545524332303a206f6e6c79206272696467652060448201527f63616e206d696e7420616e64206275726e00000000000000000000000000000060648201526084015b60405180910390fd5b6105788282610c9e565b8173ffffffffffffffffffffffffffffffffffffffff167f0f6798a560793a54c3bcfe86a93cde1e73087d944c0ea20544137d4121396885826040516105c091815260200190565b60405180910390a25050565b60606105f77f0000000000000000000000000000000000000000000000000000000000000000610d77565b6106207f0000000000000000000000000000000000000000000000000000000000000000610d77565b6106497f0000000000000000000000000000000000000000000000000000000000000000610d77565b60405160200161065b939291906112d5565b604051602081830303815290604052905090565b6060600480546103b390611243565b3373ffffffffffffffffffffffffffffffffffffffff7f000000000000000000000000000000000000000000000000000000000000000016146107295760405162461bcd60e51b815260206004820152603160248201527f4b726f6d614d696e7461626c6545524332303a206f6e6c79206272696467652060448201527f63616e206d696e7420616e64206275726e0000000000000000000000000000006064820152608401610565565b6107338282610e35565b8173ffffffffffffffffffffffffffffffffffffffff167fcc16f5dbb4873280815c1ee09dbd06736cffcc184412cf7a71a0fdb75d397ca5826040516105c091815260200190565b33600081815260016020908152604080832073ffffffffffffffffffffffffffffffffffffffff87168452909152812054909190838110156108255760405162461bcd60e51b815260206004820152602560248201527f45524332303a2064656372656173656420616c6c6f77616e63652062656c6f7760448201527f207a65726f0000000000000000000000000000000000000000000000000000006064820152608401610565565b6104678286868403610840565b600033610444818585610a7d565b73ffffffffffffffffffffffffffffffffffffffff83166108c85760405162461bcd60e51b8152602060048201526024808201527f45524332303a20617070726f76652066726f6d20746865207a65726f2061646460448201527f72657373000000000000000000000000000000000000000000000000000000006064820152608401610565565b73ffffffffffffffffffffffffffffffffffffffff82166109515760405162461bcd60e51b815260206004820152602260248201527f45524332303a20617070726f766520746f20746865207a65726f20616464726560448201527f73730000000000000000000000000000000000000000000000000000000000006064820152608401610565565b73ffffffffffffffffffffffffffffffffffffffff83811660008181526001602090815260408083209487168084529482529182902085905590518481527f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b92591015b60405180910390a3505050565b73ffffffffffffffffffffffffffffffffffffffff8381166000908152600160209081526040808320938616835292905220547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8114610a775781811015610a6a5760405162461bcd60e51b815260206004820152601d60248201527f45524332303a20696e73756666696369656e7420616c6c6f77616e63650000006044820152606401610565565b610a778484848403610840565b50505050565b73ffffffffffffffffffffffffffffffffffffffff8316610b065760405162461bcd60e51b815260206004820152602560248201527f45524332303a207472616e736665722066726f6d20746865207a65726f20616460448201527f64726573730000000000000000000000000000000000000000000000000000006064820152608401610565565b73ffffffffffffffffffffffffffffffffffffffff8216610b8f5760405162461bcd60e51b815260206004820152602360248201527f45524332303a207472616e7366657220746f20746865207a65726f206164647260448201527f65737300000000000000000000000000000000000000000000000000000000006064820152608401610565565b73ffffffffffffffffffffffffffffffffffffffff831660009081526020819052604090205481811015610c2b5760405162461bcd60e51b815260206004820152602660248201527f45524332303a207472616e7366657220616d6f756e742065786365656473206260448201527f616c616e636500000000000000000000000000000000000000000000000000006064820152608401610565565b73ffffffffffffffffffffffffffffffffffffffff848116600081815260208181526040808320878703905593871680835291849020805487019055925185815290927fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a3610a77565b73ffffffffffffffffffffffffffffffffffffffff8216610d015760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f2061646472657373006044820152606401610565565b8060026000828254610d139190611296565b909155505073ffffffffffffffffffffffffffffffffffffffff8216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b60606000610d8483610fbd565b600101905060008167ffffffffffffffff811115610da457610da461134b565b6040519080825280601f01601f191660200182016040528015610dce576020820181803683370190505b5090508181016020015b7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff017f3031323334353637383961626364656600000000000000000000000000000000600a86061a8153600a8504945084610dd857509392505050565b73ffffffffffffffffffffffffffffffffffffffff8216610ebe5760405162461bcd60e51b815260206004820152602160248201527f45524332303a206275726e2066726f6d20746865207a65726f2061646472657360448201527f73000000000000000000000000000000000000000000000000000000000000006064820152608401610565565b73ffffffffffffffffffffffffffffffffffffffff821660009081526020819052604090205481811015610f5a5760405162461bcd60e51b815260206004820152602260248201527f45524332303a206275726e20616d6f756e7420657863656564732062616c616e60448201527f63650000000000000000000000000000000000000000000000000000000000006064820152608401610565565b73ffffffffffffffffffffffffffffffffffffffff83166000818152602081815260408083208686039055600280548790039055518581529192917fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef91016109b3565b6000807a184f03e93ff9f4daa797ed6e38ed64bf6a1f0100000000000000008310611006577a184f03e93ff9f4daa797ed6e38ed64bf6a1f010000000000000000830492506040015b6d04ee2d6d415b85acef81000000008310611032576d04ee2d6d415b85acef8100000000830492506020015b662386f26fc10000831061105057662386f26fc10000830492506010015b6305f5e1008310611068576305f5e100830492506008015b612710831061107c57612710830492506004015b6064831061108e576064830492506002015b600a831061109a576001015b92915050565b6000602082840312156110b257600080fd5b81357fffffffff00000000000000000000000000000000000000000000000000000000811681146110e257600080fd5b9392505050565b60005b838110156111045781810151838201526020016110ec565b83811115610a775750506000910152565b60208152600082518060208401526111348160408501602087016110e9565b601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0169190910160400192915050565b803573ffffffffffffffffffffffffffffffffffffffff8116811461118a57600080fd5b919050565b600080604083850312156111a257600080fd5b6111ab83611166565b946020939093013593505050565b6000806000606084860312156111ce57600080fd5b6111d784611166565b92506111e560208501611166565b9150604084013590509250925092565b60006020828403121561120757600080fd5b6110e282611166565b6000806040838503121561122357600080fd5b61122c83611166565b915061123a60208401611166565b90509250929050565b600181811c9082168061125757607f821691505b602082108103611290577f4e487b7100000000000000000000000000000000000000000000000000000000600052602260045260246000fd5b50919050565b600082198211156112d0577f4e487b7100000000000000000000000000000000000000000000000000000000600052601160045260246000fd5b500190565b600084516112e78184602089016110e9565b80830190507f2e000000000000000000000000000000000000000000000000000000000000008082528551611323816001850160208a016110e9565b6001920191820152835161133e8160028401602088016110e9565b0160020195945050505050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fdfea164736f6c634300080f000a"


func init() {
	if err := json.Unmarshal([]byte(KromaMintableERC20StorageLayoutJSON), KromaMintableERC20StorageLayout); err != nil {
		panic(err)
	}

	layouts["KromaMintableERC20"] = KromaMintableERC20StorageLayout
	deployedBytecodes["KromaMintableERC20"] = KromaMintableERC20DeployedBin
	immutableReferences["KromaMintableERC20"] = true
}
