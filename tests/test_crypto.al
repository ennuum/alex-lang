# ALEX - tests du module crypto (ALEX pur). Lancer depuis la racine : ./alex run tests/test_crypto.al
# Les vecteurs ci-dessous ont été produits avec hashlib / hmac / pbkdf2_hmac / base64 de Python et la
# bibliothèque `cryptography` (ChaCha20), puis figés ici ; les vecteurs de la RFC 8439 et de la FIPS 180 y figurent aussi.
use crypto
use string
use testing
from core use len
from collections use append
from testing use assert_eq, assert_true, assert_false, assert_raises

const VECTORS := [
    ["d41d8cd98f00b204e9800998ecf8427e", "da39a3ee5e6b4b0d3255bfef95601890afd80709", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e", 0],
    ["13c8ffd977013703a701cf8e11deac65", "067d5096f219c64b53bb1c7d5e3754285b565a47", "e7cf46a078fed4fafd0b5e3aff144802b853f8ae459a4f0c14add3314b7cc3a6", "527cff2b6fdfbc0f54fe092b17d6d8c7e22500242635fa56981e85a64da6ce8a12a3a66cf69fd48f588bcba9bad141b8e351a0cdd4925ae57289933eec1fc153", 1],
    ["876d16c575f9d3d7f51f12fef37237eb", "5e8b290f00d31c341d769e40255c757924864ef3", "b39fad1a1075f64570b3226d339ea818f9c66ecd2f1c59fd8b9c5a32b54c513f", "b634899da10b86dd03ad5e7cef4279fa2addbc82a4fdc782c99d95d776ceec8777201d4acdf259e9f935fa43ff71ac7e7317220734b9f43bd9192c8bdf46ac8c", 3],
    ["d872aa0473a24da995ce4ac518ade767", "c4622048cfef59b72875839ee7ae1cbcf55e7658", "2900465fcb533e05a158fd2b3be0e5e3b03740d83060aa3580e0d98a96bf2384", "2fd061a12ae849786141611e02a18ad9dad5d1cf6980f67fd4021fe369e4fef874548e9e5146e53622a919b3dcbd652f9abdd9578c4bd0c8e28d38008ea922b5", 55],
    ["e23567645846677c205de80f9779081b", "ddc12942656468475970fa4fa49161f52ed138e4", "31454ff48ef36af2f08fd511bdc37d9d5855ac23e992e5ff5445cb6b7674a674", "78ade6b0c755effd2b093d02bbeb8354d57c3e0c36457f941b47e2b384bc0a279c4cdaae1f9968e47bfa1e94438c33af1253067677087890f35f944a6fb8693e", 56],
    ["1fe5e4a27e12484d7203d0b60c21c51f", "c3299df7d6a56509d38a55d09ccf403d4a56d044", "bcc0a5d3791b985b7550e04ca660a6c63a589ba1edd2283c8e110e5b515df124", "4e5e6def94589f306ca004ae1313f5fc2bfb4b618beaf24f1af85d7c341658ecb51033b127d8d728680754a072e85664718a7bb9a10a54cd9c7f8807accc051b", 57],
    ["4775b66278a8fc132ff80923378216cd", "7f8c3fa49f1297bd8b9feb964b6b419987f9f0d1", "5f6401b96532c36de4e65beec0409b69b1d181864c8009b7a04f43e5d56350d1", "853d2f48b4e8c74aa7c547ad831787b4f2bb85aa2851241a7fd1a38f651c2eb5816990092a4cd336d86dba73f0191f69a8825c7f5f2991bdcc2fb9661af22f46", 63],
    ["71e123b70c7aa64826fcfe472694cd1c", "a334b47180c61fd522f99905ec02c36f9e848211", "94eb5de4943613fd048dc93393ab06877405faa39c11f53e9386083339833e7e", "be7cccdacc7551d40828f4f3568f741a224ec5e5274ca547e06ad5dc8313456706033259aa46937a061bc30f9913597e0b591c6492da5334e9148bbb91ce805b", 64],
    ["5949948f26e35203661075214faa3966", "dd27d9eb923d39687e10872c3e8133ba2f0a68a1", "fc518669b6eb4b4dd91827ecacef86689c725bd5bab888fd3b26dbb196eec954", "3be887ac920f6d448401e32d90815cbff19ec9b8042d9e14bd5d289db18437736f1a00b7573607684d83dc2f398ee82f5296beae0231e5bd2fe139b20292a18c", 65],
    ["971d0e793c1b82b4ade7bd998916b4da", "aa138368b05cd08f2e4c0d7ef9be54552bb00f7f", "aeca4f5a02aead30b044df2ce00b97f2f4874c25352eaa1916a1831819dcc3dd", "4d1db900250c96436052fbca79c13acbf378aad9c35b87d94c3803264df61fd22cbd327c8938d024db372abf4208934ee09367d571d6c670bf74ee07b83e7506", 111],
    ["0940460d6eb047e4dc1442f81f696669", "28528b51ef6d26dc41f33652db6540d0f5c0f124", "cec7a189fcea0a38f025f11208b1bd2b12ec291ff00ec5448a325c5c8db0c7ac", "dfb715ca3478a894302ace39c42d1d6646e1044f2247a6274d8b42d155d2fdbe7017195e85cfba96bedc51f84c44638978a540039ff09c64cef6c0c5ccc8f7b6", 112],
    ["71b58eb1aebe1c7a4fbe1dca809939bd", "6d1ae0def5a2dfda8af7cf8414b1a1a2400accf4", "cf1a963953155c44d16895e04631102a3e8c239321e045b9a62d71eac1c4a67a", "604b00570a65f49111782330fd36bef680bcc58e13288cbec1b8554e81de17b05f53e1293d33673872d0d48a57aba35f539643a3b8210d2bef35531f2b441451", 113],
    ["87f72c7241c5fe218bb4df8c0aba3232", "bea949473b1ec34747ce121c3293624b5d9d8f84", "b0dc41b1a384e2f1203f0351b38fbeaafceef577ce1191d5bfc25da39f721eae", "ac34688c34ec5621bc2c528803513d7e126704639e5de933db3aa149cb8c3d5f6255cea97eca9ba177edc0a8931b529261bc3f0efeb93cd18e21c377c488701c", 119],
    ["bf240b8b7407fba3805adeec63a03b77", "bf05266acd3ec21592b4d42aaea97fa6f3e51926", "5df24dd802ac26132ce608dcb5f09841eef039ee0f152acf98d26d17fe4e88e6", "b4af29ca30135ba8d020f6ca575811518a1d607825506c3ca63022a1f71a6a9f4ec0dd89398f1b38a4945ffb1de61d2f72e666f98d022888319586e3da78f9a7", 120],
    ["520bdc2dbab7c25d64263ffb242d9e98", "b2b4bfd7b2112a167b77a600cca227593523c406", "0fe729ff19257bd6fec853acc2ea355f6b34b58e6c0f684c3e188fcdfcd9baae", "f93a0e7465b294188e8aa2b1cc2e98bc8d5115d46f51c7a9ec599b9d9f96a80fef6a4f226b648c89bd9eac23b3d64264898b568d915c66666c44cd0319e2ef56", 127],
    ["3e93b378458b77da96b2357c3bda8cc2", "3b1953091899492377f686c266b81d84b5d40f70", "0aedd4856f8eba0963627336ad5144a9a7dbe12498e6066f0165fc97d8ddee4c", "0b4815d35f9d07b1a30de2790e1be2a720234295cd7b4d9e9af51719ff90019f1fe6d4e402a7dcc4177085023dc460ab743dad9b2c1dda42662bda5d3b2e155b", 128],
    ["d1ae06bbf9128955a34bedb6231eee62", "4fd6558b2a93925fb7129447e1d1fac8cff56287", "4f1757ae4bffbae86d775b831765b75af154d52f7deaa46dd378051a2d3ad57f", "1809db04d02717483e04bc4333a14308bd2d0213ba7bf2c63f11eb1b8a0af8252e67fd104fd466fb95f945539824d8e4183155fa5ced0bee3dad46d9384a0bd5", 129],
    ["f9914cd8b67085ceb02d1eba3ff2dc0c", "588cf108f067a9951c1d42248e0c3a6e49afe002", "5e48d64839a8bff5e2471507af6a49f9990817df437857f4a2007df41266e1b5", "e7b33b6b94b9b5e03e34a445c198d1a3a5620d999e75ad72064c804477a91745cf6bf8a53c18b37eee5697aca1d539fcd93a594cd004242f3fd26cf468762a38", 200],
    ["c3cb8ae118768782aa1896d7fb2827ef", "2c4169b2993df842a68ce33d5a1120339ab1057f", "57799de80e3dd6e2ac4d40c41a150d1662f7f87d0d994776a2fdc37c39b0ea4e", "bef824658455c75d8ed438db9b1c2c26c705f5f0423c3b42834e0a5aded3123efc6be2da589e55e43f3d1d03e6a83134bb9781333bc63f72a0e2559d1263209d", 1000]
]

const HMACS := [
    ["md5", [], "1542a1b4eebb092b12a359e58a4fd2b4"],
    ["md5", [159, 122, 85, 48, 11], "45a2b5994e45fd28e84a4856d307ef15"],
    ["md5", [38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "9af09348c3b7dab873c7c8803bc44d90"],
    ["md5", [75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "ea11d0938d1267450128414f1df7468b"],
    ["md5", [102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "d1e6f3045fd0d91a8a0e94207c74128a"],
    ["md5", [139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "c382e648aac45c39f3783dba12ef7ec9"],
    ["md5", [206, 169, 132, 95, 58, 21, 240, 203, 166, 129, 92, 55, 18, 237, 200, 163, 126, 89, 52, 15, 234, 197, 160, 123, 86, 49, 12, 231, 194, 157, 120, 83, 46, 9, 228, 191, 154, 117, 80, 43, 6, 225, 188, 151, 114, 77, 40, 3, 222, 185, 148, 111, 74, 37, 0, 219, 182, 145, 108, 71, 34, 253, 216, 179, 142, 105, 68, 31, 250, 213, 176, 139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "4aa06470076e54383bb4b34b4db63e4c"],
    ["sha1", [], "25522e25f932995e4c38dc81ffce388d9d7ea886"],
    ["sha1", [159, 122, 85, 48, 11], "bb4f18ef692cc84592f2f663ef792c9fe83cfe81"],
    ["sha1", [38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "47b50ecd6f2ebeb29ae92e7a916a27eb14ce70fb"],
    ["sha1", [75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "4809c328eb4dd75dc7fb963c9993a6a6ade7f033"],
    ["sha1", [102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "7d392cbf1c3e209860564939c6f1a031a7b3f672"],
    ["sha1", [139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "a651a865a8360e7a7a5d8da23220f55635eee4c3"],
    ["sha1", [206, 169, 132, 95, 58, 21, 240, 203, 166, 129, 92, 55, 18, 237, 200, 163, 126, 89, 52, 15, 234, 197, 160, 123, 86, 49, 12, 231, 194, 157, 120, 83, 46, 9, 228, 191, 154, 117, 80, 43, 6, 225, 188, 151, 114, 77, 40, 3, 222, 185, 148, 111, 74, 37, 0, 219, 182, 145, 108, 71, 34, 253, 216, 179, 142, 105, 68, 31, 250, 213, 176, 139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "1318d9624852b6d067325ab518d4acabcf44692f"],
    ["sha256", [], "5a8c944a5222ecb0c3153f1e9eb4f72e77c70d42cca3979c079862ff2099994d"],
    ["sha256", [159, 122, 85, 48, 11], "8edbf561c074543263a35fc34595904a96c61826a8c24b1cf51d617dfef27c00"],
    ["sha256", [38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "58a2c221fab5a7bc107903bb32cf25559e52202f530b24f2e3b28d9d2ff42b6c"],
    ["sha256", [75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "f5b283c4331b0d0acd1d875f8ad85712f517ea0908fd90855f48c766ea02d426"],
    ["sha256", [102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "18cac0530b151de47e81ddb4e979760530b016b2dc1e3b013989c5c006416f7e"],
    ["sha256", [139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "8a4bc8313a41a1048a4f2674063f439f4d7b45a0ca5e13cb6a7dd0c421161b61"],
    ["sha256", [206, 169, 132, 95, 58, 21, 240, 203, 166, 129, 92, 55, 18, 237, 200, 163, 126, 89, 52, 15, 234, 197, 160, 123, 86, 49, 12, 231, 194, 157, 120, 83, 46, 9, 228, 191, 154, 117, 80, 43, 6, 225, 188, 151, 114, 77, 40, 3, 222, 185, 148, 111, 74, 37, 0, 219, 182, 145, 108, 71, 34, 253, 216, 179, 142, 105, 68, 31, 250, 213, 176, 139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "b8a55558e12ce11a627e9a88e9f572220ee06dfbb85fce2652d360e30573b666"],
    ["sha512", [], "d5595d4cadce2bc4034a79357bf546f2fea47eda12d123e00917ec8177a602cc9938d5175e0cb15852be35803525d7d576165004ce466351ebe0e80cf29c666e"],
    ["sha512", [159, 122, 85, 48, 11], "ade1335c82b259bcaad1555aa496407482d85735835e8edfe9dab96f50bfd38191a953406d6de0ad1d6786bcd0ddfd30636b5ff21c4ffb2c3a904125bc7ebc02"],
    ["sha512", [38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "cfbe704b5e077b736625c4ab953fc66398d3c1277e04c8a11a8ad914a9695a0bc0a1a6674760719ac332cf0c8ea08bdb126edb06f0062c03c052aa007d5effa7"],
    ["sha512", [75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "f09987ae023dc7868bbac3dac0292c99e7953dea11b70b3b044216d60d7e099f4b3e763a53fb1b2b146e125001bf2e1e796ad38eca8586b390b41b2117e3d75a"],
    ["sha512", [102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "83de3ef4f0e49205bfee47c18df2caf8ad386348ffca55f5b642efbfbe5f4b4b6c1efba630871beb7811e05f344c889d9e0cbed7cdbafd455c1b5aada63dc2aa"],
    ["sha512", [139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "c02c8b0b3cfb64332e1dbb36dd4c4c5abdc27166b68c4c7156fbe383bef430cbd8f0531d850b4d93873e401e3729ec33dcb0d3d2600e3ca817580f72c21a97a8"],
    ["sha512", [206, 169, 132, 95, 58, 21, 240, 203, 166, 129, 92, 55, 18, 237, 200, 163, 126, 89, 52, 15, 234, 197, 160, 123, 86, 49, 12, 231, 194, 157, 120, 83, 46, 9, 228, 191, 154, 117, 80, 43, 6, 225, 188, 151, 114, 77, 40, 3, 222, 185, 148, 111, 74, 37, 0, 219, 182, 145, 108, 71, 34, 253, 216, 179, 142, 105, 68, 31, 250, 213, 176, 139, 102, 65, 28, 247, 210, 173, 136, 99, 62, 25, 244, 207, 170, 133, 96, 59, 22, 241, 204, 167, 130, 93, 56, 19, 238, 201, 164, 127, 90, 53, 16, 235, 198, 161, 124, 87, 50, 13, 232, 195, 158, 121, 84, 47, 10, 229, 192, 155, 118, 81, 44, 7, 226, 189, 152, 115, 78, 41, 4, 223, 186, 149, 112, 75, 38, 1, 220, 183, 146, 109, 72, 35, 254, 217, 180, 143, 106, 69, 32, 251, 214, 177, 140, 103, 66, 29, 248, 211, 174, 137, 100, 63, 26, 245, 208, 171, 134, 97, 60, 23, 242, 205, 168, 131, 94, 57, 20, 239, 202, 165, 128, 91, 54, 17, 236, 199, 162, 125, 88, 51, 14, 233, 196, 159, 122, 85, 48, 11], "ac447ec1d42acf46d61bb6f7ce2d70b88be70355394718adfb86356366c2442e28d9780c791971200d29c94ecae4f415ab61b39d5070ea1f97eee52f0d20fa73"]
]

const PBKDF2S := [
    ["sha256", [112, 97, 115, 115, 119, 111, 114, 100], [115, 97, 108, 116], 1, 32, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"],
    ["sha256", [112, 97, 115, 115, 119, 111, 114, 100], [115, 97, 108, 116], 2, 32, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"],
    ["sha256", [112, 97, 115, 115, 119, 111, 114, 100], [115, 97, 108, 116], 50, 20, "926891811ee18e4539b150e9c3888a1afb0eb6fb"],
    ["sha1", [112, 97, 115, 115, 119, 111, 114, 100], [115, 97, 108, 116], 3, 20, "6b4e26125c25cf21ae35ead955f479ea2e71f6ff"],
    ["sha1", [112, 97, 115, 115, 119, 111, 114, 100, 80, 65, 83, 83, 87, 79, 82, 68, 112, 97, 115, 115, 119, 111, 114, 100], [115, 97, 108, 116, 83, 65, 76, 84, 115, 97, 108, 116, 83, 65, 76, 84, 115, 97, 108, 116, 83, 65, 76, 84, 115, 97, 108, 116, 83, 65, 76, 84, 115, 97, 108, 116], 4, 25, "c0011246e6454cbda3a93c197299bd3014ebc6057d8929c30e"],
    ["sha512", [112, 97, 115, 115, 119, 111, 114, 100], [115, 97, 108, 116], 5, 64, "abc073be888c36bf213a3b669e2bc892ee18f6c6444de3b921b4f345164bdc414ad35e670d3a35232dcddb8b26c5b34f852889370fd03762771989ba8b42b776"],
    ["sha512", [112, 97, 115, 115], [195, 169, 240, 159, 152, 128], 3, 100, "61fa22f8b82d587c352418ca317a2f2853d650da9fca567ed900e1b340fd4c5efbfb2de982c168bedfa30e0b8d789acb15453abbd2916f6f903cd098127bb305c81683e5a7edec5289979faeb0150331117881792f0735bf25532562e9b86a1d7f2cb2f8"],
    ["sha256", [112], [115], 2, 70, "1998f3d3f22119b7f9a77c8ae8b1df0d6e5dde8ae44a6adea8bd836734ca367379812ed24a007ecf9a6393c65872ed627ac85325377974a39cacc9a7ef46c7061ca6b1127914"],
    ["md5", [97], [98], 2, 16, "ce3c5630468c80e762c7c62f51251c0d"]
]

const BASE64S := [
    [[], "", ""],
    [[11], "Cw==", "Cw"],
    [[11, 48], "CzA=", "CzA"],
    [[11, 48, 85], "CzBV", "CzBV"],
    [[11, 48, 85, 122], "CzBVeg==", "CzBVeg"],
    [[11, 48, 85, 122, 159], "CzBVep8=", "CzBVep8"],
    [[11, 48, 85, 122, 159, 196], "CzBVep/E", "CzBVep_E"],
    [[11, 48, 85, 122, 159, 196, 233], "CzBVep/E6Q==", "CzBVep_E6Q"],
    [[11, 48, 85, 122, 159, 196, 233, 14], "CzBVep/E6Q4=", "CzBVep_E6Q4"],
    [[11, 48, 85, 122, 159, 196, 233, 14, 51], "CzBVep/E6Q4z", "CzBVep_E6Q4z"],
    [[11, 48, 85, 122, 159, 196, 233, 14, 51, 88], "CzBVep/E6Q4zWA==", "CzBVep_E6Q4zWA"],
    [[11, 48, 85, 122, 159, 196, 233, 14, 51, 88, 125], "CzBVep/E6Q4zWH0=", "CzBVep_E6Q4zWH0"],
    [[251, 255, 191, 254, 252, 253], "+/+//vz9", "-_-__vz9"]
]

const RFC8439_CT := "6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d"
const CHACHA_V2 := "26f7d8bd384e98179cb3515c2670e0906839b60e8286b8b91875b87fefe671f93fdbba770806ce4901ee058067d7d6279a52d8b26ac7f1ca87875340672aaeb2d04cd81191a28d6767e694cb73c39103fc157e019ac57a8288737e9d32ef603c84bcbc478b7f112f5d0f3588074072b3022428812fcc1d57dd0b5017b588dd152a2124e0b070f614cbb34f705fa00ce33d766350cbdefbef9c5086c1c7a2dac7853f4f2ed4223f388527c1a36d5092ba2009bfe5742e103af4a22e1c75e5ea3c4c351555ae9419be"

# Mêmes données que le générateur Python : octet i = (i*37 + 11) mod 256.
func data(n):
    out := []
    i := 0
    while i < n:
        append(out, (i * 37 + 11) % 256)
        i = i + 1
    return out

func reversed(l):
    out := []
    i := len(l) - 1
    while i >= 0:
        append(out, l[i])
        i = i - 1
    return out

func t_hash_known():
    assert_eq(crypto.md5(""), "d41d8cd98f00b204e9800998ecf8427e")
    assert_eq(crypto.md5("abc"), "900150983cd24fb0d6963f7d28e17f72")
    assert_eq(crypto.sha1(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    assert_eq(crypto.sha1("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
    assert_eq(crypto.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    assert_eq(crypto.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    assert_eq(crypto.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    assert_eq(crypto.sha512("abc"), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    assert_eq(crypto.sha512(""), "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")

func t_hash_vectors():
    for v in VECTORS:
        d := data(v[4])
        assert_eq(crypto.md5(d), v[0], "md5 n=" + str(v[4]))
        assert_eq(crypto.sha1(d), v[1], "sha1 n=" + str(v[4]))
        assert_eq(crypto.sha256(d), v[2], "sha256 n=" + str(v[4]))
        assert_eq(crypto.sha512(d), v[3], "sha512 n=" + str(v[4]))

func t_hash_api():
    assert_eq(crypto.hash_hex("sha256", "abc"), crypto.sha256("abc"))
    assert_eq(crypto.hex_encode(crypto.hash_bytes("md5", "abc")), crypto.md5("abc"))
    assert_eq(len(crypto.sha1_bytes("x")), 20)
    assert_eq(len(crypto.sha256_bytes("x")), 32)
    assert_eq(len(crypto.sha512_bytes("x")), 64)
    assert_eq(len(crypto.md5_bytes("x")), 16)
    assert_eq(crypto.sha256("é😀"), crypto.sha256(crypto.utf8_encode("é😀")))
    assert_eq(crypto.sha256((97, 98, 99)), crypto.sha256("abc"))
    long := string.repeat("a", 1000000 // 100)
    assert_eq(len(crypto.sha256(long)), 64)
    assert_raises(() => crypto.hash_hex("sha3", "x"), "ValueError", "inconnu")
    assert_raises(() => crypto.sha256(5), "TypeError")
    assert_raises(() => crypto.sha256([256]), "ValueError", "octet invalide")
    assert_raises(() => crypto.sha256([-1]), "ValueError")
    assert_raises(() => crypto.sha256(["a"]), "ValueError")

func t_hmac():
    assert_eq(crypto.hmac("sha256", "key", "The quick brown fox jumps over the lazy dog"), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    assert_eq(crypto.hmac("md5", "key", "The quick brown fox jumps over the lazy dog"), "80070713463e7749b90c2dc24911e275")
    assert_eq(crypto.hmac("sha1", "key", "The quick brown fox jumps over the lazy dog"), "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9")
    msg := string.repeat("The quick brown fox ", 3)
    for v in HMACS:
        assert_eq(crypto.hmac(v[0], v[1], msg), v[2], v[0] + " clé de " + str(len(v[1])) + " octets")
    assert_eq(crypto.hex_encode(crypto.hmac_bytes("sha256", "key", "x")), crypto.hmac("sha256", "key", "x"))
    assert_raises(() => crypto.hmac("nope", "k", "d"), "ValueError")

func t_pbkdf2():
    assert_eq(crypto.pbkdf2("password", "salt", 1, 32), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    assert_eq(crypto.pbkdf2("password", "salt", 2, 32), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
    for v in PBKDF2S:
        assert_eq(crypto.pbkdf2(v[1], v[2], v[3], v[4], v[0]), v[5], v[0] + " it=" + str(v[3]))
    assert_eq(len(crypto.pbkdf2_bytes("p", "s", 1, 5)), 5)
    assert_raises(() => crypto.pbkdf2("p", "s", 0, 8), "ValueError")
    assert_raises(() => crypto.pbkdf2("p", "s", 1, 0), "ValueError")
    assert_raises(() => crypto.pbkdf2("p", "s", 1.5, 8), "ValueError")
    assert_raises(() => crypto.pbkdf2("p", "s", 1, 8, "x"), "ValueError")

func t_encodages():
    assert_eq(crypto.hex_encode([0, 15, 16, 255]), "000f10ff")
    assert_eq(crypto.hex_decode("000F10ff"), [0, 15, 16, 255])
    assert_eq(crypto.hex_decode(""), [])
    assert_raises(() => crypto.hex_decode("abc"), "ValueError", "impaire")
    assert_raises(() => crypto.hex_decode("zz"), "ValueError", "non hexadécimal")
    assert_raises(() => crypto.hex_encode([300]), "ValueError")
    assert_eq(crypto.utf8_encode("aé€😀"), [97, 195, 169, 226, 130, 172, 240, 159, 152, 128])
    assert_eq(crypto.utf8_decode([97, 195, 169, 226, 130, 172, 240, 159, 152, 128]), "aé€😀")
    assert_eq(crypto.utf8_decode([]), "")
    for bad in [[195], [128], [195, 40], [224, 128, 128], [237, 160, 128], [240, 143, 191, 191], [244, 144, 128, 128], [255], [226, 130], [192, 128]]:
        assert_raises(() => crypto.utf8_decode(bad), "ValueError")
    assert_raises(() => crypto.utf8_encode(5), "TypeError")

func t_base64():
    for v in BASE64S:
        assert_eq(crypto.base64_encode(v[0]), v[1])
        assert_eq(crypto.base64_decode(v[1]), v[0])
        assert_eq(crypto.base64_encode(v[0], true), v[2])
        assert_eq(crypto.base64_decode(v[2], true), v[0])
    assert_eq(crypto.base64_decode("TWFu\nTWFu"), crypto.utf8_encode("ManMan"))
    assert_eq(crypto.base64_decode("TQ"), [77])
    assert_eq(crypto.base64_encode(crypto.utf8_encode("é")), "w6k=")
    for bad in ["T", "TWF*", "TQ=a", "TQ===", "T=", "=TQ"]:
        assert_raises(() => crypto.base64_decode(bad), "ValueError")
    assert_raises(() => crypto.base64_decode("+/", true), "ValueError")
    assert_raises(() => crypto.base64_decode(5), "TypeError")

func t_equals():
    assert_true(crypto.equals("abc", "abc"))
    assert_false(crypto.equals("abc", "abd"))
    assert_false(crypto.equals("abc", "ab"))
    assert_true(crypto.equals([1, 2], [1, 2]))
    assert_true(crypto.equals("", ""))
    assert_true(crypto.equals(crypto.hmac("sha256", "k", "m"), crypto.hmac("sha256", "k", "m")))

func t_chacha20():
    key := data(0)
    i := 0
    while i < 32:
        append(key, i)
        i = i + 1
    nonce := [0, 0, 0, 0, 0, 0, 0, 74, 0, 0, 0, 0]
    pt := "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
    ct := crypto.chacha20(key, nonce, pt, 1)
    assert_eq(crypto.hex_encode(ct), RFC8439_CT)
    assert_eq(crypto.utf8_decode(crypto.chacha20(key, nonce, ct, 1)), pt)
    key2 := []
    n2 := []
    pt2 := []
    j := 0
    while j < 32:
        append(key2, (j * 7 + 3) % 256)
        j = j + 1
    j = 0
    while j < 12:
        append(n2, (j * 13 + 1) % 256)
        j = j + 1
    j = 0
    while j < 200:
        append(pt2, (j * 29 + 5) % 256)
        j = j + 1
    assert_eq(crypto.hex_encode(crypto.chacha20(key2, n2, pt2, 0)), CHACHA_V2)
    assert_eq(crypto.chacha20(key, nonce, [], 1), [])
    assert_raises(() => crypto.chacha20([1], nonce, "x"), "ValueError", "32 octets")
    assert_raises(() => crypto.chacha20(key, [1], "x"), "ValueError", "12 octets")
    assert_raises(() => crypto.chacha20(key, nonce, "x", -1), "ValueError")
    assert_raises(() => crypto.chacha20(key, nonce, "x", 4294967296), "ValueError")

func t_chiffrer_puis_authentifier():
    key := []
    k := 0
    while k < 32:
        append(key, 200 - k)
        k = k + 1
    nonce := [9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2]
    secret := "message confidentiel é😀"
    ct := crypto.chacha20(key, nonce, secret)
    tag := crypto.hmac_bytes("sha256", key, ct)
    assert_true(crypto.equals(tag, crypto.hmac_bytes("sha256", key, ct)))
    ct[0] = ct[0] ^ 1
    assert_false(crypto.equals(tag, crypto.hmac_bytes("sha256", key, ct)))
    ct[0] = ct[0] ^ 1
    assert_eq(crypto.utf8_decode(crypto.chacha20(key, nonce, ct)), secret)

testing.test("hachages connus", t_hash_known)
testing.test("hachages : vecteurs hashlib (frontières de bloc)", t_hash_vectors)
testing.test("hachages : API", t_hash_api)
testing.test("hmac", t_hmac)
testing.test("pbkdf2", t_pbkdf2)
testing.test("hex et utf-8", t_encodages)
testing.test("base64", t_base64)
testing.test("equals", t_equals)
testing.test("chacha20 (RFC 8439)", t_chacha20)
testing.test("chiffrer puis authentifier", t_chiffrer_puis_authentifier)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) crypto en échec")
print("CRYPTO: OK")
