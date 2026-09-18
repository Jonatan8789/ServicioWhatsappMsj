(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };

  // node_modules/@digitalpersona/core/dist/es5.bundles/index.umd.js
  var require_index_umd = __commonJS({
    "node_modules/@digitalpersona/core/dist/es5.bundles/index.umd.js"(exports, module) {
      (function(global, factory) {
        typeof exports === "object" && typeof module !== "undefined" ? factory(exports) : typeof define === "function" && define.amd ? define(["exports"], factory) : (global = global || self, factory((global.dp = global.dp || {}, global.dp.core = global.dp.core || {})));
      })(exports, function(exports2) {
        "use strict";
        var Url = (
          /** @class */
          (function() {
            function Url2(base, path, query) {
              this.href = Url2.create(base, path, query);
            }
            Url2.getSanitizedQuery = function(query) {
              return Object.keys(query).map(function(key) {
                return [key, query[key]].map(encodeURIComponent).join("=");
              }).join("&");
            };
            Url2.create = function(base, path, query) {
              return base + (path ? "/" + encodeURI(path) : "") + (query ? "?" + Url2.getSanitizedQuery(query) : "");
            };
            return Url2;
          })()
        );
        (function(BioFactor) {
          BioFactor[BioFactor["Multiple"] = 1] = "Multiple";
          BioFactor[BioFactor["FacialFeatures"] = 2] = "FacialFeatures";
          BioFactor[BioFactor["Voice"] = 4] = "Voice";
          BioFactor[BioFactor["Fingerprint"] = 8] = "Fingerprint";
          BioFactor[BioFactor["Iris"] = 16] = "Iris";
          BioFactor[BioFactor["Retina"] = 32] = "Retina";
          BioFactor[BioFactor["HandGeometry"] = 64] = "HandGeometry";
          BioFactor[BioFactor["SignatureDynamics"] = 128] = "SignatureDynamics";
          BioFactor[BioFactor["KeystrokeDynamics"] = 256] = "KeystrokeDynamics";
          BioFactor[BioFactor["LipMovement"] = 512] = "LipMovement";
          BioFactor[BioFactor["ThermalFaceImage"] = 1024] = "ThermalFaceImage";
          BioFactor[BioFactor["ThermalHandImage"] = 2048] = "ThermalHandImage";
          BioFactor[BioFactor["Gait"] = 4096] = "Gait";
        })(exports2.BioFactor || (exports2.BioFactor = {}));
        (function(BioSampleFormatOwner) {
          BioSampleFormatOwner[BioSampleFormatOwner["None"] = 0] = "None";
          BioSampleFormatOwner[BioSampleFormatOwner["Neurotechnologija"] = 49] = "Neurotechnologija";
          BioSampleFormatOwner[BioSampleFormatOwner["DigitalPersona"] = 51] = "DigitalPersona";
          BioSampleFormatOwner[BioSampleFormatOwner["Cognitec"] = 99] = "Cognitec";
          BioSampleFormatOwner[BioSampleFormatOwner["Innovatrics"] = 53] = "Innovatrics";
        })(exports2.BioSampleFormatOwner || (exports2.BioSampleFormatOwner = {}));
        var BioSampleFormat = (
          /** @class */
          /* @__PURE__ */ (function() {
            function BioSampleFormat2(FormatOwner, FormatID) {
              this.FormatOwner = FormatOwner;
              this.FormatID = FormatID;
            }
            return BioSampleFormat2;
          })()
        );
        (function(BioSampleType) {
          BioSampleType[BioSampleType["Raw"] = 1] = "Raw";
          BioSampleType[BioSampleType["Intermediate"] = 2] = "Intermediate";
          BioSampleType[BioSampleType["Processed"] = 4] = "Processed";
          BioSampleType[BioSampleType["RawWSQCompressed"] = 8] = "RawWSQCompressed";
          BioSampleType[BioSampleType["Encrypted"] = 16] = "Encrypted";
          BioSampleType[BioSampleType["Signed"] = 32] = "Signed";
        })(exports2.BioSampleType || (exports2.BioSampleType = {}));
        (function(BioSamplePurpose) {
          BioSamplePurpose[BioSamplePurpose["Any"] = 0] = "Any";
          BioSamplePurpose[BioSamplePurpose["Verify"] = 1] = "Verify";
          BioSamplePurpose[BioSamplePurpose["Identify"] = 2] = "Identify";
          BioSamplePurpose[BioSamplePurpose["Enroll"] = 3] = "Enroll";
          BioSamplePurpose[BioSamplePurpose["EnrollForVerificationOnly"] = 4] = "EnrollForVerificationOnly";
          BioSamplePurpose[BioSamplePurpose["EnrollForIdentificationOnly"] = 5] = "EnrollForIdentificationOnly";
          BioSamplePurpose[BioSamplePurpose["Audit"] = 6] = "Audit";
        })(exports2.BioSamplePurpose || (exports2.BioSamplePurpose = {}));
        (function(BioSampleEncryption) {
          BioSampleEncryption[BioSampleEncryption["None"] = 0] = "None";
          BioSampleEncryption[BioSampleEncryption["XTEA"] = 1] = "XTEA";
        })(exports2.BioSampleEncryption || (exports2.BioSampleEncryption = {}));
        var BioSampleHeader = (
          /** @class */
          /* @__PURE__ */ (function() {
            function BioSampleHeader2(Factor, Format, Type, Purpose, Quality, Encryption) {
              this.Factor = Factor;
              this.Format = Format;
              this.Type = Type;
              this.Purpose = Purpose;
              this.Quality = Quality;
              this.Encryption = Encryption;
            }
            return BioSampleHeader2;
          })()
        );
        var BioSample = (
          /** @class */
          /* @__PURE__ */ (function() {
            function BioSample2(Header, Data) {
              this.Header = Header;
              this.Data = Data;
              this.Version = 1;
            }
            return BioSample2;
          })()
        );
        var __assign = function() {
          __assign = Object.assign || function __assign2(t) {
            for (var s, i = 1, n = arguments.length; i < n; i++) {
              s = arguments[i];
              for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p)) t[p] = s[p];
            }
            return t;
          };
          return __assign.apply(this, arguments);
        };
        function __read(o, n) {
          var m = typeof Symbol === "function" && o[Symbol.iterator];
          if (!m) return o;
          var i = m.call(o), r, ar = [], e;
          try {
            while ((n === void 0 || n-- > 0) && !(r = i.next()).done) ar.push(r.value);
          } catch (error) {
            e = { error };
          } finally {
            try {
              if (r && !r.done && (m = i["return"])) m.call(i);
            } finally {
              if (e) throw e.error;
            }
          }
          return ar;
        }
        function __spread() {
          for (var ar = [], i = 0; i < arguments.length; i++)
            ar = ar.concat(__read(arguments[i]));
          return ar;
        }
        var Utf16 = (
          /** @class */
          (function() {
            function Utf162() {
            }
            Utf162.fromUtf8 = function(s) {
              return decodeURIComponent(escape(Utf8.noBom(s)));
            };
            Utf162.fromBase64 = function(s) {
              return Utf162.fromUtf8(Utf8.fromBase64(s));
            };
            Utf162.fromBase64Url = function(s) {
              return Utf162.fromUtf8(Utf8.fromBase64Url(s));
            };
            Utf162.withBom = function(s) {
              return "\uFEFF" + s;
            };
            Utf162.noBom = function(s) {
              return s.replace(/^\uFEFF/, "");
            };
            return Utf162;
          })()
        );
        var Utf8 = (
          /** @class */
          (function() {
            function Utf82() {
            }
            Utf82.fromUtf16 = function(s) {
              return unescape(encodeURIComponent(Utf16.noBom(s)));
            };
            Utf82.fromBase64 = function(s) {
              return atob(s);
            };
            Utf82.fromBase64Url = function(s) {
              return Utf82.fromBase64(Base64.fromBase64Url(s));
            };
            Utf82.fromBytes = function(bytes) {
              return String.fromCharCode.apply(String, __spread(bytes));
            };
            Utf82.withBom = function(s) {
              return "\xEF\xBB\xBF" + s;
            };
            Utf82.noBom = function(s) {
              return s.replace(/^\xEF\xBB\xBF/, "");
            };
            return Utf82;
          })()
        );
        var Base64 = (
          /** @class */
          (function() {
            function Base642() {
            }
            Base642.fromUtf8 = function(s) {
              return btoa(s);
            };
            Base642.fromUtf16 = function(s) {
              return Base642.fromUtf8(Utf8.fromUtf16(s));
            };
            Base642.fromBase64Url = function(s) {
              return (s.length % 4 === 2 ? s + "==" : s.length % 4 === 3 ? s + "=" : s).replace(/-/g, "+").replace(/_/g, "/");
            };
            Base642.fromBytes = function(bytes) {
              return Base642.fromUtf8(Utf8.fromBytes(bytes));
            };
            Base642.fromJSON = function(obj) {
              return Base642.fromUtf16(JSON.stringify(obj));
            };
            return Base642;
          })()
        );
        var Base64Url = (
          /** @class */
          (function() {
            function Base64Url2() {
            }
            Base64Url2.fromBase64 = function(s) {
              return s.replace(/\=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
            };
            Base64Url2.fromUtf8 = function(s) {
              return Base64Url2.fromBase64(Base64.fromUtf8(s));
            };
            Base64Url2.fromUtf16 = function(s) {
              return Base64Url2.fromBase64(Base64.fromUtf16(s));
            };
            Base64Url2.fromBytes = function(bytes) {
              return Base64Url2.fromUtf8(Utf8.fromBytes(bytes));
            };
            Base64Url2.fromJSON = function(obj) {
              return Base64Url2.fromUtf16(JSON.stringify(obj));
            };
            return Base64Url2;
          })()
        );
        var Base32 = (
          /** @class */
          (function() {
            function Base322() {
            }
            Base322.fromBytes = function(bytes) {
              var digits = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
              var v1 = 0, v2 = 0, v3 = 0, v4 = 0, v5 = 0, str = "", l = bytes.length, i = 0;
              var count = Math.floor(l / 5) * 5;
              while (i < count) {
                v1 = bytes[i++];
                v2 = bytes[i++];
                v3 = bytes[i++];
                v4 = bytes[i++];
                v5 = bytes[i++];
                str += digits[v1 >>> 3] + digits[(v1 << 2 | v2 >>> 6) & 31] + digits[v2 >>> 1 & 31] + digits[(v2 << 4 | v3 >>> 4) & 31] + digits[(v3 << 1 | v4 >>> 7) & 31] + digits[v4 >>> 2 & 31] + digits[(v4 << 3 | v5 >>> 5) & 31] + digits[v5 & 31];
              }
              var remain = l - count;
              if (remain === 0)
                return str;
              switch (remain) {
                // @ts-ignore no-switch-case-fall-through
                case 4:
                  v4 = bytes[--l];
                // @ts-ignore no-switch-case-fall-through
                case 3:
                  v3 = bytes[--l];
                // @ts-ignore no-switch-case-fall-through
                case 2:
                  v2 = bytes[--l];
                // @ts-ignore no-switch-case-fall-through
                case 1:
                  v1 = bytes[--l];
              }
              str += digits[v1 >>> 3];
              switch (remain) {
                case 1:
                  return str + digits[v1 << 2 & 31] + "======";
                case 2:
                  return str + digits[(v1 << 2 | v2 >>> 6) & 31] + digits[v2 >>> 1 & 31] + digits[v2 << 4 & 31] + "====";
                case 3:
                  return str + digits[(v1 << 2 | v2 >>> 6) & 31] + digits[v2 >>> 1 & 31] + digits[(v2 << 4 | v3 >>> 4) & 31] + digits[v3 << 1 & 31] + "===";
                case 4:
                  return str + digits[(v1 << 2 | v2 >>> 6) & 31] + digits[v2 >>> 1 & 31] + digits[(v2 << 4 | v3 >>> 4) & 31] + digits[(v3 << 1 | v4 >>> 7) & 31] + digits[v4 >>> 2 & 31] + digits[v4 << 3 & 31] + "=";
              }
              return str;
            };
            return Base322;
          })()
        );
        (function(UserNameType) {
          UserNameType[UserNameType["Unknown"] = 0] = "Unknown";
          UserNameType[UserNameType["NetBIOSDomain"] = 1] = "NetBIOSDomain";
          UserNameType[UserNameType["DNSDomain"] = 2] = "DNSDomain";
          UserNameType[UserNameType["SAM"] = 3] = "SAM";
          UserNameType[UserNameType["Simple"] = 4] = "Simple";
          UserNameType[UserNameType["UID"] = 5] = "UID";
          UserNameType[UserNameType["UPN"] = 6] = "UPN";
          UserNameType[UserNameType["Display"] = 7] = "Display";
          UserNameType[UserNameType["SID"] = 8] = "SID";
          UserNameType[UserNameType["DP"] = 9] = "DP";
        })(exports2.UserNameType || (exports2.UserNameType = {}));
        var User = (
          /** @class */
          (function() {
            function User2(name, type) {
              var reGUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
              this.name = name || "";
              this.type = type || (this.name.length === 0 ? exports2.UserNameType.Unknown : this.name === "*" ? exports2.UserNameType.Unknown : this.name.indexOf("@") !== -1 ? exports2.UserNameType.UPN : this.name.indexOf("\\") !== -1 ? exports2.UserNameType.SAM : reGUID.test(this.name) ? exports2.UserNameType.UID : exports2.UserNameType.DP);
            }
            User2.prototype.isAnonymous = function() {
              return !this.name || this.name.length === 0;
            };
            User2.prototype.isEveryone = function() {
              return this.name === "*";
            };
            User2.Anonymous = function() {
              return new User2("", exports2.UserNameType.Unknown);
            };
            User2.Everyone = function() {
              return new User2("*", exports2.UserNameType.Unknown);
            };
            User2.fromJWT = function(token, type) {
              var claims = JWT.claims(token);
              var user = claims.sub && claims.sub instanceof User2 ? claims.sub : claims.wan ? new User2(claims.wan, type) : claims.sub ? new User2(claims.sub, type || exports2.UserNameType.DP) : User2.Anonymous();
              return user;
            };
            return User2;
          })()
        );
        var JWTHeader = (
          /** @class */
          /* @__PURE__ */ (function() {
            function JWTHeader2(typ, alg, cty) {
              this.typ = typ;
              this.cty = cty;
              this.alg = alg;
            }
            return JWTHeader2;
          })()
        );
        var JWT = (
          /** @class */
          (function() {
            function JWT2() {
            }
            JWT2.claims = function(jwt) {
              var parts = jwt.split(".");
              var header = JSON.parse(Utf16.fromBase64Url(parts[0]));
              if (header.cty === "JWT") {
                return __assign(__assign({}, header), new JWTHeader());
              } else {
                var payload = JSON.parse(Utf16.fromBase64Url(parts[1]));
                if (typeof payload.sub === "object") {
                  var _a = payload.sub, name_1 = _a.name, type = _a.type;
                  payload.sub = new User(name_1, type);
                }
                return payload;
              }
            };
            JWT2.errors = function(jwt) {
              var e = [];
              var claims = JWT2.claims(jwt);
              var now = (/* @__PURE__ */ new Date()).getTime() / 1e3;
              if (claims.iat && claims.nbf && claims.iat > claims.nbf)
                e.push(new Error("JWT.Error.IssueTimeLaterThanNotBefore"));
              if (claims.nbf && claims.nbf > now)
                e.push(new Error("JWT.Error.NotEffectiveYet"));
              if (claims.exp && claims.exp <= now)
                e.push(new Error("JWT.Error.Expired"));
              return e.length > 0 ? e : null;
            };
            return JWT2;
          })()
        );
        (function(ClaimName) {
          ClaimName["TokensId"] = "jti";
          ClaimName["IssuerName"] = "iss";
          ClaimName["IssuedAt"] = "iat";
          ClaimName["Audience"] = "aud";
          ClaimName["NotBefore"] = "nbf";
          ClaimName["ExpiresAfter"] = "exp";
          ClaimName["SubjectName"] = "sub";
          ClaimName["IssuerDomain"] = "dom";
          ClaimName["SubjectUid"] = "uid";
          ClaimName["ADGuid"] = "ad_guid";
          ClaimName["CredentialsUsed"] = "crd";
          ClaimName["Group"] = "group";
          ClaimName["Role"] = "role";
          ClaimName["WindowsAccountName"] = "wan";
          ClaimName["T24Principal"] = "t24";
        })(exports2.ClaimName || (exports2.ClaimName = {}));
        var Ticket = (
          /** @class */
          (function() {
            function Ticket2(jwt) {
              this.jwt = jwt;
            }
            Ticket2.None = function() {
              return new Ticket2("");
            };
            return Ticket2;
          })()
        );
        var Credential = (
          /** @class */
          (function() {
            function Credential2(id, data, encode) {
              if (encode === void 0) {
                encode = true;
              }
              this.id = id;
              this.data = !data ? null : !encode ? JSON.stringify(data) : Base64Url.fromUtf16(typeof data !== "string" ? JSON.stringify(data) : data);
            }
            Credential2.None = function() {
              return new Credential2("");
            };
            Credential2.Any = function() {
              return new Credential2("*");
            };
            Credential2.Password = "D1A1F561-E14A-4699-9138-2EB523E132CC";
            Credential2.Fingerprints = "AC184A13-60AB-40E5-A514-E10F777EC2F9";
            Credential2.Face = "85AEAA44-413B-4DC1-AF09-ADE15892730A";
            Credential2.SmartCard = "D66CC98D-4153-4987-8EBE-FB46E848EA98";
            Credential2.ContactlessCard = "F674862D-AC70-48CA-B73E-64A22F3BAC44";
            Credential2.ProximityCard = "1F31360C-81C0-4EE0-9ACD-5A4400F66CC2";
            Credential2.PIN = "8A6FCEC3-3C8A-40C2-8AC0-A039EC01BA05";
            Credential2.SecurityQuestions = "B49E99C6-6C94-42DE-ACD7-FD6B415DF503";
            Credential2.Bluetooth = "E750A180-577B-47F7-ACD9-F89A7E27FA49";
            Credential2.OneTimePassword = "324C38BD-0B51-4E4D-BD75-200DA0C8177F";
            Credential2.U2F = "5D5F73AF-BCE5-4161-9584-42A61AED0E48";
            Credential2.IWA = "AE922666-9667-49BC-97DA-1EB0E1EF73D2";
            Credential2.Email = "7845D71D-AB67-4EA7-913C-F81E75C3A087";
            Credential2.Behavior = "193C41F6-5CF6-4525-84CC-223603DAC9AB";
            Credential2.Cards = "FCFA704C-144B-42DB-8DF3-13F5CD20C525";
            return Credential2;
          })()
        );
        (function(FingerPosition) {
          FingerPosition[FingerPosition["Unknown"] = 0] = "Unknown";
          FingerPosition[FingerPosition["RightThumb"] = 1] = "RightThumb";
          FingerPosition[FingerPosition["RightIndex"] = 2] = "RightIndex";
          FingerPosition[FingerPosition["RightMiddle"] = 3] = "RightMiddle";
          FingerPosition[FingerPosition["RightRing"] = 4] = "RightRing";
          FingerPosition[FingerPosition["RightLittle"] = 5] = "RightLittle";
          FingerPosition[FingerPosition["LeftThumb"] = 6] = "LeftThumb";
          FingerPosition[FingerPosition["LeftIndex"] = 7] = "LeftIndex";
          FingerPosition[FingerPosition["LeftMiddle"] = 8] = "LeftMiddle";
          FingerPosition[FingerPosition["LeftRing"] = 9] = "LeftRing";
          FingerPosition[FingerPosition["LeftLittle"] = 10] = "LeftLittle";
        })(exports2.FingerPosition || (exports2.FingerPosition = {}));
        var Finger = (
          /** @class */
          (function() {
            function Finger2(position) {
              this.position = position;
            }
            Finger2.fromJson = function(json) {
              var obj = json;
              return new Finger2(obj.position);
            };
            return Finger2;
          })()
        );
        (function(FaceImageType) {
          FaceImageType[FaceImageType["Jpeg"] = 1] = "Jpeg";
        })(exports2.FaceImageType || (exports2.FaceImageType = {}));
        var FaceImage = (
          /** @class */
          (function() {
            function FaceImage2(ImageData, ImageType) {
              if (ImageType === void 0) {
                ImageType = exports2.FaceImageType.Jpeg;
              }
              this.ImageData = ImageData;
              this.ImageType = ImageType;
              this.Version = 1;
            }
            FaceImage2.fromDataURL = function(image) {
              return new FaceImage2(image.replace("data:image/jpeg;base64,", ""));
            };
            FaceImage2.fromCanvas = function(canvas, quality) {
              if (quality === void 0) {
                quality = 1;
              }
              return FaceImage2.fromDataURL(canvas.toDataURL("image/jpeg", quality));
            };
            FaceImage2.prototype.toBioSample = function(format, purpose, sdkVersion) {
              if (format === void 0) {
                format = new BioSampleFormat(exports2.BioSampleFormatOwner.None, 0);
              }
              if (purpose === void 0) {
                purpose = exports2.BioSamplePurpose.Any;
              }
              return new BioSample(new BioSampleHeader(exports2.BioFactor.FacialFeatures, format, exports2.BioSampleType.Raw, purpose, -1, exports2.BioSampleEncryption.None), Base64Url.fromJSON(this));
            };
            return FaceImage2;
          })()
        );
        (function(QuestionType) {
          QuestionType[QuestionType["Regular"] = 0] = "Regular";
          QuestionType[QuestionType["Custom"] = 1] = "Custom";
        })(exports2.QuestionType || (exports2.QuestionType = {}));
        var Question = (
          /** @class */
          (function() {
            function Question2(number, lang_id, sublang_id, keyboard_layout, text) {
              this.number = number;
              this.lang_id = lang_id;
              this.sublang_id = sublang_id;
              this.keyboard_layout = keyboard_layout;
              this.text = text;
              this.version = 1;
              this.type = number <= 100 ? exports2.QuestionType.Regular : exports2.QuestionType.Custom;
              if (this.type === exports2.QuestionType.Custom && !text)
                throw new Error("Question text is required for custom questions");
            }
            Question2.fromJson = function(json) {
              var obj = json;
              return new Question2(obj.number, obj.lang_id, obj.sublang_id, obj.keyboard_layout, obj.text);
            };
            return Question2;
          })()
        );
        var Answer = (
          /** @class */
          /* @__PURE__ */ (function() {
            function Answer2(question, text) {
              this.text = text;
              this.number = question instanceof Question ? question.number : question;
            }
            return Answer2;
          })()
        );
        exports2.Answer = Answer;
        exports2.Base32 = Base32;
        exports2.Base64 = Base64;
        exports2.Base64Url = Base64Url;
        exports2.BioSample = BioSample;
        exports2.BioSampleFormat = BioSampleFormat;
        exports2.BioSampleHeader = BioSampleHeader;
        exports2.Credential = Credential;
        exports2.FaceImage = FaceImage;
        exports2.Finger = Finger;
        exports2.JWT = JWT;
        exports2.Question = Question;
        exports2.Ticket = Ticket;
        exports2.Url = Url;
        exports2.User = User;
        exports2.Utf16 = Utf16;
        exports2.Utf8 = Utf8;
        Object.defineProperty(exports2, "__esModule", { value: true });
      });
    }
  });

  // node_modules/@digitalpersona/services/dist/es5.bundles/index.umd.js
  var require_index_umd2 = __commonJS({
    "node_modules/@digitalpersona/services/dist/es5.bundles/index.umd.js"(exports, module) {
      (function(global, factory) {
        typeof exports === "object" && typeof module !== "undefined" ? factory(exports, require_index_umd()) : typeof define === "function" && define.amd ? define(["exports", "@digitalpersona/core"], factory) : (global = global || self, factory((global.dp = global.dp || {}, global.dp.services = global.dp.services || {}), global.dp.core));
      })(exports, function(exports2, core) {
        "use strict";
        (function(VarType) {
          VarType[VarType["Boolean"] = 1] = "Boolean";
          VarType[VarType["Integer"] = 2] = "Integer";
          VarType[VarType["String"] = 3] = "String";
          VarType[VarType["Blob"] = 4] = "Blob";
        })(exports2.VarType || (exports2.VarType = {}));
        var VarBool = (
          /** @class */
          /* @__PURE__ */ (function() {
            function VarBool2(values) {
              this.values = values;
              this.type = exports2.VarType.Boolean;
            }
            return VarBool2;
          })()
        );
        var VarInt = (
          /** @class */
          /* @__PURE__ */ (function() {
            function VarInt2(values) {
              this.values = values;
              this.type = exports2.VarType.Integer;
            }
            return VarInt2;
          })()
        );
        var VarString = (
          /** @class */
          /* @__PURE__ */ (function() {
            function VarString2(values) {
              this.values = values;
              this.type = exports2.VarType.String;
            }
            return VarString2;
          })()
        );
        var VarBlob = (
          /** @class */
          /* @__PURE__ */ (function() {
            function VarBlob2(values) {
              this.values = values;
              this.type = exports2.VarType.Blob;
            }
            return VarBlob2;
          })()
        );
        (function(AttributeAction) {
          AttributeAction[AttributeAction["Clear"] = 1] = "Clear";
          AttributeAction[AttributeAction["Update"] = 2] = "Update";
          AttributeAction[AttributeAction["Append"] = 3] = "Append";
          AttributeAction[AttributeAction["Delete"] = 4] = "Delete";
        })(exports2.AttributeAction || (exports2.AttributeAction = {}));
        (function(ResourceActions) {
          ResourceActions[ResourceActions["Read"] = 0] = "Read";
          ResourceActions[ResourceActions["Write"] = 1] = "Write";
          ResourceActions[ResourceActions["Delete"] = 2] = "Delete";
        })(exports2.ResourceActions || (exports2.ResourceActions = {}));
        var extendStatics = function(d, b) {
          extendStatics = Object.setPrototypeOf || { __proto__: [] } instanceof Array && function(d2, b2) {
            d2.__proto__ = b2;
          } || function(d2, b2) {
            for (var p in b2) if (b2.hasOwnProperty(p)) d2[p] = b2[p];
          };
          return extendStatics(d, b);
        };
        function __extends(d, b) {
          extendStatics(d, b);
          function __() {
            this.constructor = d;
          }
          d.prototype = b === null ? Object.create(b) : (__.prototype = b.prototype, new __());
        }
        var __assign = function() {
          __assign = Object.assign || function __assign2(t) {
            for (var s, i = 1, n = arguments.length; i < n; i++) {
              s = arguments[i];
              for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p)) t[p] = s[p];
            }
            return t;
          };
          return __assign.apply(this, arguments);
        };
        var ServiceError = (
          /** @class */
          (function(_super) {
            __extends(ServiceError2, _super);
            function ServiceError2(code, message) {
              var _newTarget = this.constructor;
              var _this = _super.call(this, message) || this;
              _this.code = code;
              Object.setPrototypeOf(_this, _newTarget.prototype);
              return _this;
            }
            ServiceError2.fromServiceFault = function(fault) {
              return new ServiceError2(fault.error_code, fault.description);
            };
            ServiceError2.prototype.isHttpError = function() {
              return this.code >= 400 && this.code < 600;
            };
            return ServiceError2;
          })(Error)
        );
        (function(DatabaseType) {
          DatabaseType["AD"] = "AD";
          DatabaseType["LDS"] = "ADLDS";
        })(exports2.DatabaseType || (exports2.DatabaseType = {}));
        var AuthenticationData = (
          /** @class */
          /* @__PURE__ */ (function() {
            function AuthenticationData2() {
            }
            return AuthenticationData2;
          })()
        );
        (function(AuthenticationStatus) {
          AuthenticationStatus[AuthenticationStatus["Error"] = 0] = "Error";
          AuthenticationStatus[AuthenticationStatus["Continue"] = 1] = "Continue";
          AuthenticationStatus[AuthenticationStatus["Completed"] = 2] = "Completed";
        })(exports2.AuthenticationStatus || (exports2.AuthenticationStatus = {}));
        var ServiceEndpoint = (
          /** @class */
          (function() {
            function ServiceEndpoint2(endpointUrl, defaultRequest) {
              this.defaultRequest = {
                cache: "no-cache",
                mode: "cors",
                headers: {
                  "Content-Type": "application/json;charset=utf-8",
                  "Accept": "application/json"
                }
              };
              this.endpointUrl = endpointUrl;
              this.defaultRequest = defaultRequest || this.defaultRequest;
            }
            ServiceEndpoint2.handleResponse = function(response) {
              return response.ok ? response.json() : ServiceEndpoint2.handleError(response);
            };
            ServiceEndpoint2.handleError = function(response) {
              if (response.status === 404) {
                return response.json().then(function(fault) {
                  throw fault ? new ServiceError(fault.error_code, fault.description) : new ServiceError(response.status, response.statusText);
                });
              }
              throw new ServiceError(response.status, response.statusText);
            };
            ServiceEndpoint2.prototype.get = function(path, query, request) {
              return fetch(core.Url.create(this.endpointUrl, path, query), __assign(__assign(__assign({}, this.defaultRequest), request), { method: "GET" })).then(ServiceEndpoint2.handleResponse);
            };
            ServiceEndpoint2.prototype.post = function(path, query, body, request) {
              return fetch(core.Url.create(this.endpointUrl, path, query), __assign(__assign(__assign(__assign({}, this.defaultRequest), request), { method: "POST" }), body ? { body: JSON.stringify(body) } : {})).then(ServiceEndpoint2.handleResponse);
            };
            ServiceEndpoint2.prototype.put = function(path, query, body, request) {
              return fetch(core.Url.create(this.endpointUrl, path, query), __assign(__assign(__assign(__assign({}, this.defaultRequest), request), { method: "PUT" }), body ? { body: JSON.stringify(body) } : {})).then(ServiceEndpoint2.handleResponse);
            };
            ServiceEndpoint2.prototype.del = function(path, query, body, request) {
              return fetch(core.Url.create(this.endpointUrl, path, query), __assign(__assign(__assign(__assign({}, this.defaultRequest), request), { method: "DELETE" }), body ? { body: JSON.stringify(body) } : {})).then(ServiceEndpoint2.handleResponse);
            };
            ServiceEndpoint2.prototype.ping = function(path) {
              if (path === void 0) {
                path = "Ping";
              }
              return fetch(core.Url.create(this.endpointUrl, path), __assign(__assign({}, this.defaultRequest), { method: "GET" })).then(function(response) {
                return response.ok;
              }).catch(function(reason) {
                return false;
              });
            };
            return ServiceEndpoint2;
          })()
        );
        var Service = (
          /** @class */
          (function() {
            function Service2(endpoint) {
              this.endpoint = new ServiceEndpoint(endpoint);
            }
            Service2.prototype.Ping = function() {
              return this.endpoint.ping();
            };
            return Service2;
          })()
        );
        var AuthService = (
          /** @class */
          (function(_super) {
            __extends(AuthService2, _super);
            function AuthService2(endpointUrl) {
              return _super.call(this, endpointUrl) || this;
            }
            AuthService2.prototype.GetUserCredentials = function(user) {
              return this.endpoint.get("GetUserCredentials", { user: user.name, type: user.type }).then(function(response) {
                return response.GetUserCredentialsResult;
              });
            };
            AuthService2.prototype.GetEnrollmentData = function(user, credentialId) {
              return this.endpoint.get("GetEnrollmentData", { user: user.name, type: user.type, cred_id: credentialId }).then(function(response) {
                return response.GetEnrollmentDataResult;
              });
            };
            AuthService2.prototype.Identify = function(credential) {
              return this.endpoint.post("IdentifyUser", null, { credential }).then(function(response) {
                return new core.Ticket(response.IdentifyUserResult.jwt);
              });
            };
            AuthService2.prototype.Authenticate = function(identity, credential) {
              return identity instanceof core.Ticket ? this.endpoint.post("AuthenticateUserTicket", null, { ticket: identity, credential }).then(function(response) {
                return new core.Ticket(response.AuthenticateUserTicketResult.jwt);
              }) : this.endpoint.post("AuthenticateUser", null, { user: identity, credential }).then(function(response) {
                return new core.Ticket(response.AuthenticateUserResult.jwt);
              });
            };
            AuthService2.prototype.CustomAction = function(actionId, ticket, user, credential) {
              return this.endpoint.post("CustomAction", null, { actionId, ticket, user, credential }).then(function(response) {
                return response.CustomActionResult;
              });
            };
            AuthService2.prototype.CreateAuthentication = function(identity, credentialId) {
              return identity instanceof core.Ticket ? this.endpoint.post("CreateTicketAuthentication", null, { ticket: identity, credentialId }).then(function(response) {
                return response.CreateTicketAuthenticationResult;
              }) : this.endpoint.post("CreateUserAuthentication", null, { user: identity, credentialId }).then(function(response) {
                return response.CreateUserAuthenticationResult;
              });
            };
            AuthService2.prototype.ContinueAuthentication = function(authId, authData) {
              return this.endpoint.post("ContinueAuthentication", null, { authId, authData }).then(function(response) {
                return response.ContinueAuthenticationResult;
              });
            };
            AuthService2.prototype.DestroyAuthentication = function(authId) {
              return this.endpoint.del("DestroyAuthentication", null, { authId });
            };
            return AuthService2;
          })(Service)
        );
        var ClaimRequest = (
          /** @class */
          /* @__PURE__ */ (function() {
            function ClaimRequest2(name, db, attr) {
              this.name = name;
              this.db = db;
              this.attr = attr;
            }
            return ClaimRequest2;
          })()
        );
        var ClaimsService = (
          /** @class */
          (function(_super) {
            __extends(ClaimsService2, _super);
            function ClaimsService2(endpointUrl) {
              return _super.call(this, endpointUrl) || this;
            }
            ClaimsService2.prototype.GetConfiguredClaims = function(ticket) {
              return this.endpoint.post("GetConfiguredClaims", null, { ticket }).then(function(result) {
                return result.GetConfiguredClaimsResult.ticket;
              });
            };
            ClaimsService2.prototype.GetClaims = function(ticket, request) {
              return this.endpoint.post("GetClaims", null, { ticket, request }).then(function(result) {
                return result.GetClaimsResult.ticket;
              });
            };
            return ClaimsService2;
          })(Service)
        );
        var EnrollService = (
          /** @class */
          (function(_super) {
            __extends(EnrollService2, _super);
            function EnrollService2(endpointUrl) {
              return _super.call(this, endpointUrl) || this;
            }
            EnrollService2.prototype.GetUserCredentials = function(user) {
              return this.endpoint.get("GetUserCredentials", { user: user.name, type: user.type }).then(function(result) {
                return result.GetUserCredentialsResult;
              });
            };
            EnrollService2.prototype.GetEnrollmentData = function(user, credentialId) {
              return this.endpoint.get("GetEnrollmentData", { user: user.name, type: user.type, cred_id: credentialId }).then(function(result) {
                return result.GetEnrollmentDataResult;
              });
            };
            EnrollService2.prototype.CreateUser = function(secOfficer, user, password) {
              return this.endpoint.put("CreateUser", null, { secOfficer, user, password });
            };
            EnrollService2.prototype.DeleteUser = function(secOfficer, user) {
              return this.endpoint.del("DeleteUser", null, { secOfficer, user });
            };
            EnrollService2.prototype.EnrollUserCredentials = function(secOfficer, owner, credential) {
              return this.endpoint.put("EnrollUserCredentials", null, { secOfficer, owner, credential });
            };
            EnrollService2.prototype.DeleteUserCredentials = function(secOfficer, owner, credential) {
              return this.endpoint.del("DeleteUserCredentials", null, { secOfficer, owner, credential });
            };
            EnrollService2.prototype.EnrollAltusUserCredentials = function(secOfficer, user, credential) {
              return this.endpoint.put("EnrollAltusUserCredentials", null, { secOfficer, user, credential });
            };
            EnrollService2.prototype.DeleteAltusUserCredentials = function(secOfficer, user, credential) {
              return this.endpoint.del("DeleteAltusUserCredentials", null, { secOfficer, user, credential });
            };
            EnrollService2.prototype.GetUserAttribute = function(ticket, user, attributeName) {
              return this.endpoint.post("GetUserAttribute", null, { ticket, user, attributeName }).then(function(result) {
                return {
                  name: attributeName,
                  data: result.GetUserAttributeResult
                };
              });
            };
            EnrollService2.prototype.PutUserAttribute = function(ticket, user, attribute, action) {
              return this.endpoint.put("PutUserAttribute", null, {
                ticket,
                user,
                action,
                attributeName: attribute.name,
                attributeData: attribute.data
              });
            };
            EnrollService2.prototype.UnlockUser = function(user, credential) {
              return this.endpoint.post("UnlockUser", null, { user, credential });
            };
            EnrollService2.prototype.CustomAction = function(ticket, user, credential, actionId) {
              return this.endpoint.post("CustomAction", null, { ticket, user, credential, actionId }).then(function(result) {
                return result.CustomActionResult;
              });
            };
            EnrollService2.prototype.IsEnrollmentAllowed = function(secOfficer, user, credentialId) {
              return this.endpoint.post("IsEnrollmentAllowed", null, { secOfficer, user, credentialId });
            };
            return EnrollService2;
          })(Service)
        );
        var ContextualInfo = (
          /** @class */
          /* @__PURE__ */ (function() {
            function ContextualInfo2() {
            }
            return ContextualInfo2;
          })()
        );
        (function(TriggerName) {
          TriggerName["Behavior"] = "behavior";
          TriggerName["IP"] = "ip";
          TriggerName["Device"] = "device";
          TriggerName["AltusInstalled"] = "altusInstalled";
          TriggerName["Computer"] = "computer";
          TriggerName["Domain"] = "domain";
          TriggerName["User"] = "user";
          TriggerName["InsideFirewall"] = "insideFirewall";
          TriggerName["RemoteSession"] = "remoteSession";
        })(exports2.TriggerName || (exports2.TriggerName = {}));
        var PolicyService = (
          /** @class */
          (function(_super) {
            __extends(PolicyService2, _super);
            function PolicyService2(endpointUrl) {
              return _super.call(this, endpointUrl) || this;
            }
            PolicyService2.prototype.GetPolicyInfo = function(user, resourceUri, action, info) {
              return this.endpoint.post("GetPolicyInfo", null, { user, resourceUri, action, info }).then(function(result) {
                return result.GetPolicyInfoResult;
              });
            };
            return PolicyService2;
          })(Service)
        );
        var SecretService = (
          /** @class */
          (function(_super) {
            __extends(SecretService2, _super);
            function SecretService2(endpointUrl) {
              return _super.call(this, endpointUrl) || this;
            }
            SecretService2.prototype.GetAuthPolicy = function(user, secretName, action) {
              return this.endpoint.get("GetAuthPolicy", { user: user.name, type: user.type, secretName, action }).then(function(result) {
                return result.GetAuthPolicyResult;
              });
            };
            SecretService2.prototype.DoesSecretExist = function(user, secretName) {
              return this.endpoint.get("DoesSecretExist", { user: user.name, type: user.type, secretName }).then(function(result) {
                return result.DoesSecretExistResult;
              });
            };
            SecretService2.prototype.ReadSecret = function(ticket, secretName) {
              return this.endpoint.post("ReadSecret", null, { ticket, secretName }).then(function(result) {
                return result.ReadSecretResult;
              });
            };
            SecretService2.prototype.WriteSecret = function(ticket, secretName, secretData) {
              return this.endpoint.put("WriteSecret", null, { ticket, secretName, secretData });
            };
            SecretService2.prototype.DeleteSecret = function(ticket, secretName) {
              return this.endpoint.del("DeleteSecret", null, { ticket, secretName });
            };
            return SecretService2;
          })(Service)
        );
        (function(LicenseType) {
          LicenseType[LicenseType["ADUser"] = 1] = "ADUser";
          LicenseType[LicenseType["LDSUser"] = 2] = "LDSUser";
        })(exports2.LicenseType || (exports2.LicenseType = {}));
        (function(SearchScope) {
          SearchScope[SearchScope["Base"] = 0] = "Base";
          SearchScope[SearchScope["OneLevel"] = 1] = "OneLevel";
          SearchScope[SearchScope["Subtree"] = 2] = "Subtree";
        })(exports2.SearchScope || (exports2.SearchScope = {}));
        (function(ServerSettingType) {
          ServerSettingType[ServerSettingType["Unknown"] = 0] = "Unknown";
          ServerSettingType[ServerSettingType["Admin"] = 1] = "Admin";
          ServerSettingType[ServerSettingType["Public"] = 2] = "Public";
        })(exports2.ServerSettingType || (exports2.ServerSettingType = {}));
        (function(ServerSettings) {
          ServerSettings[ServerSettings["LockoutThreshold"] = 0] = "LockoutThreshold";
          ServerSettings[ServerSettings["LockoutDuration"] = 1] = "LockoutDuration";
          ServerSettings[ServerSettings["LockoutReset"] = 2] = "LockoutReset";
        })(exports2.ServerSettings || (exports2.ServerSettings = {}));
        (function(UACFlags) {
          UACFlags[UACFlags["RevertToWindows"] = 1] = "RevertToWindows";
          UACFlags[UACFlags["PasswordNotAllowed"] = 2] = "PasswordNotAllowed";
          UACFlags[UACFlags["PinRequired"] = 4] = "PinRequired";
          UACFlags[UACFlags["FingerprintRequired"] = 8] = "FingerprintRequired";
          UACFlags[UACFlags["FingerprintOnly"] = 16] = "FingerprintOnly";
          UACFlags[UACFlags["OtpAndPwd"] = 64] = "OtpAndPwd";
          UACFlags[UACFlags["OtpAndFingerprint"] = 128] = "OtpAndFingerprint";
        })(exports2.UACFlags || (exports2.UACFlags = {}));
        (function(UserAccountType) {
          UserAccountType[UserAccountType["Unknown"] = 0] = "Unknown";
          UserAccountType[UserAccountType["Local"] = 1] = "Local";
          UserAccountType[UserAccountType["ActiveDirectory"] = 2] = "ActiveDirectory";
          UserAccountType[UserAccountType["ADLDS"] = 3] = "ADLDS";
        })(exports2.UserAccountType || (exports2.UserAccountType = {}));
        var AdminService = (
          /** @class */
          (function(_super) {
            __extends(AdminService2, _super);
            function AdminService2(endpointUrl) {
              return _super.call(this, endpointUrl) || this;
            }
            AdminService2.prototype.ExecuteSearch = function(ticket, query) {
              return this.endpoint.post("ExecuteSearch", null, __assign({ ticket }, query)).then(function(response) {
                return JSON.parse(response.ExecuteSearchResult);
              });
            };
            AdminService2.prototype.PSKCImport = function(ticket, PSKCData, PSKCFileName, password, sharedKey) {
              return this.endpoint.post("PSKCImport", null, { ticket, PSKCData, PSKCFileName, password, sharedKey }).then(function(response) {
                return response.PSKCImportResult;
              });
            };
            AdminService2.prototype.GetServerSettings = function(ticket, user, settings) {
              return this.endpoint.post("GetServerSettings", null, { ticket, user, settings }).then(function(response) {
                return response.GetServerSettingsResult;
              });
            };
            AdminService2.prototype.SetServerSettings = function(ticket, type, settings) {
              return this.endpoint.put("SetServerSettings", null, { ticket, type, settings });
            };
            AdminService2.prototype.GetLicenseInfo = function(type) {
              return this.endpoint.get("GetLicenseInfo", { type }).then(function(response) {
                return response.GetLicenseInfoResult;
              });
            };
            AdminService2.prototype.GetUserRecoveryPassword = function(ticket, user, encryptedPwd) {
              return this.endpoint.post("GetUserRecoveryPassword", null, { ticket, user, encryptedPwd }).then(function(response) {
                return response.GetUserRecoveryPasswordResult;
              });
            };
            AdminService2.prototype.AdminDeleteUserCredentials = function(ticket, user, credentials) {
              return this.endpoint.del("AdminDeleteUserCredentials", null, { ticket, user, credentials });
            };
            AdminService2.prototype.GetUserInfo = function(ticket, user) {
              return this.endpoint.post("GetUserInfo", null, { ticket, user }).then(function(response) {
                return response.GetUserInfoResult;
              });
            };
            AdminService2.prototype.UnlockUserAccount = function(ticket, user) {
              return this.endpoint.put("UnlockUserAccount", null, { ticket, user });
            };
            AdminService2.prototype.SetUserAccountControl = function(ticket, user, control) {
              return this.endpoint.put("SetUserAccountControl", null, { ticket, user, control });
            };
            return AdminService2;
          })(Service)
        );
        exports2.AdminService = AdminService;
        exports2.AuthService = AuthService;
        exports2.AuthenticationData = AuthenticationData;
        exports2.ClaimRequest = ClaimRequest;
        exports2.ClaimsService = ClaimsService;
        exports2.ContextualInfo = ContextualInfo;
        exports2.EnrollService = EnrollService;
        exports2.PolicyService = PolicyService;
        exports2.SecretService = SecretService;
        exports2.ServiceError = ServiceError;
        exports2.VarBlob = VarBlob;
        exports2.VarBool = VarBool;
        exports2.VarInt = VarInt;
        exports2.VarString = VarString;
        Object.defineProperty(exports2, "__esModule", { value: true });
      });
    }
  });

  // node_modules/@digitalpersona/devices/dist/es5.bundles/index.umd.js
  var require_index_umd3 = __commonJS({
    "node_modules/@digitalpersona/devices/dist/es5.bundles/index.umd.js"(exports, module) {
      (function(global, factory) {
        typeof exports === "object" && typeof module !== "undefined" ? factory(exports, require_index_umd(), require_index_umd2()) : typeof define === "function" && define.amd ? define(["exports", "@digitalpersona/core", "WebSdk"], factory) : (global = global || self, factory((global.dp = global.dp || {}, global.dp.devices = global.dp.devices || {}), global.dp.core));
      })(exports, function(exports2, core) {
        "use strict";
        var extendStatics = function(d, b) {
          extendStatics = Object.setPrototypeOf || { __proto__: [] } instanceof Array && function(d2, b2) {
            d2.__proto__ = b2;
          } || function(d2, b2) {
            for (var p in b2) if (b2.hasOwnProperty(p)) d2[p] = b2[p];
          };
          return extendStatics(d, b);
        };
        function __extends(d, b) {
          extendStatics(d, b);
          function __() {
            this.constructor = d;
          }
          d.prototype = b === null ? Object.create(b) : (__.prototype = b.prototype, new __());
        }
        var Event = (
          /** @class */
          /* @__PURE__ */ (function() {
            function Event2(type) {
              this.type = type;
            }
            return Event2;
          })()
        );
        var CommunicationFailed = (
          /** @class */
          (function(_super) {
            __extends(CommunicationFailed2, _super);
            function CommunicationFailed2() {
              return _super.call(this, "CommunicationFailed") || this;
            }
            return CommunicationFailed2;
          })(Event)
        );
        var DeviceEvent = (
          /** @class */
          (function(_super) {
            __extends(DeviceEvent2, _super);
            function DeviceEvent2(type, deviceId) {
              var _this = _super.call(this, type) || this;
              _this.deviceId = deviceId;
              return _this;
            }
            return DeviceEvent2;
          })(Event)
        );
        var DeviceConnected = (
          /** @class */
          (function(_super) {
            __extends(DeviceConnected2, _super);
            function DeviceConnected2(deviceId) {
              return _super.call(this, "DeviceConnected", deviceId) || this;
            }
            return DeviceConnected2;
          })(DeviceEvent)
        );
        var DeviceDisconnected = (
          /** @class */
          (function(_super) {
            __extends(DeviceDisconnected2, _super);
            function DeviceDisconnected2(deviceId) {
              return _super.call(this, "DeviceDisconnected", deviceId) || this;
            }
            return DeviceDisconnected2;
          })(DeviceEvent)
        );
        (function(CardType) {
          CardType[CardType["Contact"] = 1] = "Contact";
          CardType[CardType["Contactless"] = 2] = "Contactless";
          CardType[CardType["Proximity"] = 4] = "Proximity";
        })(exports2.CardType || (exports2.CardType = {}));
        (function(CardAttributes) {
          CardAttributes[CardAttributes["SupportsPIN"] = 1] = "SupportsPIN";
          CardAttributes[CardAttributes["SupportsUID"] = 2] = "SupportsUID";
          CardAttributes[CardAttributes["IsPKI"] = 65536] = "IsPKI";
          CardAttributes[CardAttributes["IsPIV"] = 131072] = "IsPIV";
          CardAttributes[CardAttributes["IsReadOnly"] = 2147483648] = "IsReadOnly";
        })(exports2.CardAttributes || (exports2.CardAttributes = {}));
        var CardInserted = (
          /** @class */
          (function(_super) {
            __extends(CardInserted2, _super);
            function CardInserted2(reader, card) {
              var _this = _super.call(this, "CardInserted", reader) || this;
              _this.cardId = card;
              return _this;
            }
            return CardInserted2;
          })(DeviceEvent)
        );
        var CardRemoved = (
          /** @class */
          (function(_super) {
            __extends(CardRemoved2, _super);
            function CardRemoved2(reader, card) {
              var _this = _super.call(this, "CardRemoved", reader) || this;
              _this.cardId = card;
              return _this;
            }
            return CardRemoved2;
          })(DeviceEvent)
        );
        var MultiCastEventSource = (
          /** @class */
          (function() {
            function MultiCastEventSource2() {
              this.handlers = {};
            }
            MultiCastEventSource2.prototype._on = function(event, handler) {
              this.handlers[event] = this.handlers[event] || [];
              this.handlers[event].push(handler);
              return handler;
            };
            MultiCastEventSource2.prototype._off = function(event, handler) {
              if (event) {
                var hh = this.handlers[event];
                if (hh) {
                  if (handler)
                    this.handlers[event] = hh.filter(function(h) {
                      return h !== handler;
                    });
                  else
                    delete this.handlers[event];
                }
              } else
                this.handlers = {};
              return this;
            };
            MultiCastEventSource2.prototype.emit = function(event) {
              var _this = this;
              if (!event)
                return;
              var eventName = event.type;
              var unicast = this["on" + eventName];
              if (unicast)
                this.invoke(unicast, event);
              var multicast = this.handlers[eventName];
              if (multicast)
                multicast.forEach(function(h) {
                  return _this.invoke(h, event);
                });
            };
            MultiCastEventSource2.prototype.invoke = function(handler, event) {
              try {
                handler(event);
              } catch (e) {
                console.error(e);
              }
            };
            return MultiCastEventSource2;
          })()
        );
        var MessageType;
        (function(MessageType2) {
          MessageType2[MessageType2["Response"] = 0] = "Response";
          MessageType2[MessageType2["Notification"] = 1] = "Notification";
        })(MessageType || (MessageType = {}));
        var Channel = (
          /** @class */
          (function() {
            function Channel2(channelName, options) {
              this.pending = [];
              this.webChannel = new WebSdk.WebChannelClient(channelName, options);
              this.webChannel.onConnectionSucceed = this.onConnectionSucceed.bind(this);
              this.webChannel.onConnectionFailed = this.onConnectionFailed.bind(this);
              this.webChannel.onDataReceivedTxt = this.onDataReceivedTxt.bind(this);
            }
            Channel2.prototype.send = function(request, timeout) {
              var deferred = new Promise(function(resolve, reject) {
                request.resolve = resolve;
                request.reject = reject;
                if (timeout) {
                  request.timer = window.setTimeout(function() {
                    if (request.timer)
                      try {
                        request.reject(new Error("Timeout"));
                      } catch (e) {
                      }
                  }, timeout);
                }
              });
              this.pending.push(request);
              if (this.webChannel.isConnected())
                this.processRequestQueue();
              else
                this.webChannel.connect();
              return deferred;
            };
            Channel2.prototype.onConnectionSucceed = function() {
              this.processRequestQueue();
            };
            Channel2.prototype.onConnectionFailed = function() {
              this.pending.forEach(function(r) {
                return r.reject(new Error("Communication failure."));
              });
              this.pending = [];
              if (this.onCommunicationError)
                try {
                  this.onCommunicationError();
                } catch (e) {
                }
            };
            Channel2.prototype.onDataReceivedTxt = function(data) {
              var message = JSON.parse(core.Utf8.fromBase64Url(data));
              if (message.Type === MessageType.Response) {
                var response = JSON.parse(core.Utf8.fromBase64Url(message.Data || ""));
                var request = this.findRequest(response);
                if (request !== null) {
                  if (request.timer) {
                    window.clearTimeout(request.timer);
                    delete request.timer;
                  }
                  var hr = response.Result >>> 0;
                  if (hr > 2147483647)
                    request.reject(new Error("0x" + hr.toString(16)));
                  else
                    request.resolve(response);
                } else
                  console.log("Orphaned response: " + message.Type);
              } else if (message.Type === MessageType.Notification) {
                var notification = JSON.parse(core.Utf8.fromBase64Url(message.Data || ""));
                if (this.onNotification)
                  try {
                    this.onNotification(notification);
                  } catch (e) {
                  }
              } else
                console.log("Unknown message type: " + message.Type);
            };
            Channel2.prototype.processRequestQueue = function() {
              var _this = this;
              this.pending.forEach(function(req, i, items) {
                if (!req.sent) {
                  _this.webChannel.sendDataTxt(core.Base64Url.fromJSON(req.command));
                  items[i].sent = true;
                }
              });
            };
            Channel2.prototype.findRequest = function(response) {
              for (var i = 0; i < this.pending.length; i++) {
                var request = this.pending[i];
                if (request.sent && request.command.Method === response.Method) {
                  this.pending.splice(i, 1);
                  return request;
                }
              }
              return null;
            };
            return Channel2;
          })()
        );
        var Command = (
          /** @class */
          /* @__PURE__ */ (function() {
            function Command2(method, parameters) {
              this.Method = method;
              this.Parameters = parameters;
            }
            return Command2;
          })()
        );
        var Request = (
          /** @class */
          /* @__PURE__ */ (function() {
            function Request2(command) {
              this.command = command;
              this.sent = false;
            }
            return Request2;
          })()
        );
        var Method;
        (function(Method2) {
          Method2[Method2["EnumerateReaders"] = 1] = "EnumerateReaders";
          Method2[Method2["EnumerateCards"] = 2] = "EnumerateCards";
          Method2[Method2["GetCardInfo"] = 3] = "GetCardInfo";
          Method2[Method2["GetCardUID"] = 4] = "GetCardUID";
          Method2[Method2["GetDPCardAuthData"] = 5] = "GetDPCardAuthData";
          Method2[Method2["GetDPCardEnrollData"] = 6] = "GetDPCardEnrollData";
          Method2[Method2["Subscribe"] = 100] = "Subscribe";
          Method2[Method2["Unsubscribe"] = 101] = "Unsubscribe";
        })(Method || (Method = {}));
        var NotificationType;
        (function(NotificationType2) {
          NotificationType2[NotificationType2["ReaderConnected"] = 1] = "ReaderConnected";
          NotificationType2[NotificationType2["ReaderDisconnected"] = 2] = "ReaderDisconnected";
          NotificationType2[NotificationType2["CardInserted"] = 3] = "CardInserted";
          NotificationType2[NotificationType2["CardRemoved"] = 4] = "CardRemoved";
        })(NotificationType || (NotificationType = {}));
        var CardsReader = (
          /** @class */
          (function(_super) {
            __extends(CardsReader2, _super);
            function CardsReader2(options) {
              var _this = _super.call(this) || this;
              _this.channel = new Channel("smartcards", options);
              _this.channel.onCommunicationError = _this.onConnectionFailed.bind(_this);
              _this.channel.onNotification = _this.processNotification.bind(_this);
              return _this;
            }
            CardsReader2.prototype.on = function(event, handler) {
              return this._on(event, handler);
            };
            CardsReader2.prototype.off = function(event, handler) {
              return this._off(event, handler);
            };
            CardsReader2.prototype.enumerateReaders = function() {
              return this.channel.send(new Request(new Command(Method.EnumerateReaders))).then(function(response) {
                var list = JSON.parse(core.Utf8.fromBase64Url(response.Data || "{}"));
                return JSON.parse(list.Readers || "[]");
              });
            };
            CardsReader2.prototype.enumerateCards = function() {
              return this.channel.send(new Request(new Command(Method.EnumerateCards))).then(function(response) {
                var list = JSON.parse(core.Utf8.fromBase64Url(response.Data || "{}"));
                var cards = JSON.parse(list.Cards || "[]");
                return cards.map(function(s) {
                  return JSON.parse(core.Utf16.fromBase64Url(s));
                });
              });
            };
            CardsReader2.prototype.getCardInfo = function(reader) {
              return this.channel.send(new Request(new Command(Method.GetCardInfo, core.Base64Url.fromJSON({ Reader: reader })))).then(function(response) {
                var cardInfo = JSON.parse(core.Utf8.fromBase64Url(response.Data || "null"));
                return cardInfo;
              });
            };
            CardsReader2.prototype.getCardUid = function(reader) {
              return this.channel.send(new Request(new Command(Method.GetCardUID, core.Base64Url.fromJSON({ Reader: reader })))).then(function(response) {
                var data = core.Base64.fromBase64Url(response.Data || "");
                return data;
              });
            };
            CardsReader2.prototype.getCardAuthData = function(reader, pin) {
              return this.channel.send(new Request(new Command(Method.GetDPCardAuthData, core.Base64Url.fromJSON({ Reader: reader, PIN: pin || "" })))).then(function(response) {
                var data = JSON.parse(core.Utf8.fromBase64Url(response.Data || ""));
                return data;
              });
            };
            CardsReader2.prototype.getCardEnrollData = function(reader, pin) {
              return this.channel.send(new Request(new Command(Method.GetDPCardEnrollData, core.Base64Url.fromJSON({ Reader: reader, PIN: pin || "" })))).then(function(response) {
                var data = JSON.parse(core.Utf8.fromBase64Url(response.Data || ""));
                return data;
              });
            };
            CardsReader2.prototype.subscribe = function(reader) {
              return this.channel.send(new Request(new Command(Method.Subscribe, reader ? core.Base64Url.fromJSON({ Reader: reader }) : ""))).then();
            };
            CardsReader2.prototype.unsubscribe = function(reader) {
              return this.channel.send(new Request(new Command(Method.Unsubscribe, reader ? core.Base64Url.fromJSON({ Reader: reader }) : ""))).then();
            };
            CardsReader2.prototype.onConnectionFailed = function() {
              this.emit(new CommunicationFailed());
            };
            CardsReader2.prototype.processNotification = function(notification) {
              switch (notification.Event) {
                case NotificationType.ReaderConnected:
                  return this.emit(new DeviceConnected(notification.Reader));
                case NotificationType.ReaderDisconnected:
                  return this.emit(new DeviceDisconnected(notification.Reader));
                case NotificationType.CardInserted:
                  return this.emit(new CardInserted(notification.Reader, notification.Card));
                case NotificationType.CardRemoved:
                  return this.emit(new CardRemoved(notification.Reader, notification.Card));
                default:
                  console.log("Unknown notification: " + notification.Event);
              }
            };
            return CardsReader2;
          })(
            MultiCastEventSource
            //    implements CommunicationEventSource, DeviceEventSource, CardsEventSource
          )
        );
        (function(DeviceUidType) {
          DeviceUidType[DeviceUidType["Persistent"] = 0] = "Persistent";
          DeviceUidType[DeviceUidType["Volatile"] = 1] = "Volatile";
        })(exports2.DeviceUidType || (exports2.DeviceUidType = {}));
        (function(DeviceModality) {
          DeviceModality[DeviceModality["Unknown"] = 0] = "Unknown";
          DeviceModality[DeviceModality["Swipe"] = 1] = "Swipe";
          DeviceModality[DeviceModality["Area"] = 2] = "Area";
          DeviceModality[DeviceModality["AreaMultifinger"] = 3] = "AreaMultifinger";
        })(exports2.DeviceModality || (exports2.DeviceModality = {}));
        (function(DeviceTechnology) {
          DeviceTechnology[DeviceTechnology["Unknown"] = 0] = "Unknown";
          DeviceTechnology[DeviceTechnology["Optical"] = 1] = "Optical";
          DeviceTechnology[DeviceTechnology["Capacitive"] = 2] = "Capacitive";
          DeviceTechnology[DeviceTechnology["Thermal"] = 3] = "Thermal";
          DeviceTechnology[DeviceTechnology["Pressure"] = 4] = "Pressure";
        })(exports2.DeviceTechnology || (exports2.DeviceTechnology = {}));
        (function(SampleFormat) {
          SampleFormat[SampleFormat["Raw"] = 1] = "Raw";
          SampleFormat[SampleFormat["Intermediate"] = 2] = "Intermediate";
          SampleFormat[SampleFormat["Compressed"] = 3] = "Compressed";
          SampleFormat[SampleFormat["PngImage"] = 5] = "PngImage";
        })(exports2.SampleFormat || (exports2.SampleFormat = {}));
        (function(QualityCode) {
          QualityCode[QualityCode["Good"] = 0] = "Good";
          QualityCode[QualityCode["NoImage"] = 1] = "NoImage";
          QualityCode[QualityCode["TooLight"] = 2] = "TooLight";
          QualityCode[QualityCode["TooDark"] = 3] = "TooDark";
          QualityCode[QualityCode["TooNoisy"] = 4] = "TooNoisy";
          QualityCode[QualityCode["LowContrast"] = 5] = "LowContrast";
          QualityCode[QualityCode["NotEnoughFeatures"] = 6] = "NotEnoughFeatures";
          QualityCode[QualityCode["NotCentered"] = 7] = "NotCentered";
          QualityCode[QualityCode["NotAFinger"] = 8] = "NotAFinger";
          QualityCode[QualityCode["TooHigh"] = 9] = "TooHigh";
          QualityCode[QualityCode["TooLow"] = 10] = "TooLow";
          QualityCode[QualityCode["TooLeft"] = 11] = "TooLeft";
          QualityCode[QualityCode["TooRight"] = 12] = "TooRight";
          QualityCode[QualityCode["TooStrange"] = 13] = "TooStrange";
          QualityCode[QualityCode["TooFast"] = 14] = "TooFast";
          QualityCode[QualityCode["TooSkewed"] = 15] = "TooSkewed";
          QualityCode[QualityCode["TooShort"] = 16] = "TooShort";
          QualityCode[QualityCode["TooSlow"] = 17] = "TooSlow";
          QualityCode[QualityCode["ReverseMotion"] = 18] = "ReverseMotion";
          QualityCode[QualityCode["PressureTooHard"] = 19] = "PressureTooHard";
          QualityCode[QualityCode["PressureTooLight"] = 20] = "PressureTooLight";
          QualityCode[QualityCode["WetFinger"] = 21] = "WetFinger";
          QualityCode[QualityCode["FakeFinger"] = 22] = "FakeFinger";
          QualityCode[QualityCode["TooSmall"] = 23] = "TooSmall";
          QualityCode[QualityCode["RotatedTooMuch"] = 24] = "RotatedTooMuch";
        })(exports2.QualityCode || (exports2.QualityCode = {}));
        var SamplesAcquired = (
          /** @class */
          (function(_super) {
            __extends(SamplesAcquired2, _super);
            function SamplesAcquired2(deviceUid, sampleFormat, sampleData) {
              var _this = _super.call(this, "SamplesAcquired", deviceUid) || this;
              _this.sampleFormat = sampleFormat;
              _this.samples = JSON.parse(sampleData);
              return _this;
            }
            return SamplesAcquired2;
          })(DeviceEvent)
        );
        var QualityReported = (
          /** @class */
          (function(_super) {
            __extends(QualityReported2, _super);
            function QualityReported2(deviceUid, quality) {
              var _this = _super.call(this, "QualityReported", deviceUid) || this;
              _this.quality = quality;
              return _this;
            }
            return QualityReported2;
          })(DeviceEvent)
        );
        var ErrorOccurred = (
          /** @class */
          (function(_super) {
            __extends(ErrorOccurred2, _super);
            function ErrorOccurred2(deviceUid, error) {
              var _this = _super.call(this, "ErrorOccurred", deviceUid) || this;
              _this.error = error;
              return _this;
            }
            return ErrorOccurred2;
          })(DeviceEvent)
        );
        var AcquisitionStarted = (
          /** @class */
          (function(_super) {
            __extends(AcquisitionStarted2, _super);
            function AcquisitionStarted2(deviceUid) {
              return _super.call(this, "AcquisitionStarted", deviceUid) || this;
            }
            return AcquisitionStarted2;
          })(DeviceEvent)
        );
        var AcquisitionStopped = (
          /** @class */
          (function(_super) {
            __extends(AcquisitionStopped2, _super);
            function AcquisitionStopped2(deviceUid) {
              return _super.call(this, "AcquisitionStopped", deviceUid) || this;
            }
            return AcquisitionStopped2;
          })(DeviceEvent)
        );
        var Method$1;
        (function(Method2) {
          Method2[Method2["EnumerateDevices"] = 1] = "EnumerateDevices";
          Method2[Method2["GetDeviceInfo"] = 2] = "GetDeviceInfo";
          Method2[Method2["StartAcquisition"] = 3] = "StartAcquisition";
          Method2[Method2["StopAcquisition"] = 4] = "StopAcquisition";
        })(Method$1 || (Method$1 = {}));
        var NotificationType$1;
        (function(NotificationType2) {
          NotificationType2[NotificationType2["Completed"] = 0] = "Completed";
          NotificationType2[NotificationType2["Error"] = 1] = "Error";
          NotificationType2[NotificationType2["Disconnected"] = 2] = "Disconnected";
          NotificationType2[NotificationType2["Connected"] = 3] = "Connected";
          NotificationType2[NotificationType2["Quality"] = 4] = "Quality";
          NotificationType2[NotificationType2["Stopped"] = 10] = "Stopped";
          NotificationType2[NotificationType2["Started"] = 11] = "Started";
        })(NotificationType$1 || (NotificationType$1 = {}));
        var FingerprintReader = (
          /** @class */
          (function(_super) {
            __extends(FingerprintReader2, _super);
            function FingerprintReader2(options) {
              var _this = _super.call(this) || this;
              _this.options = options;
              _this.channel = new Channel("fingerprints", _this.options);
              _this.channel.onCommunicationError = _this.onConnectionFailed.bind(_this);
              _this.channel.onNotification = _this.processNotification.bind(_this);
              return _this;
            }
            FingerprintReader2.prototype.on = function(event, handler) {
              return this._on(event, handler);
            };
            FingerprintReader2.prototype.off = function(event, handler) {
              return this._off(event, handler);
            };
            FingerprintReader2.prototype.enumerateDevices = function() {
              return this.channel.send(new Request(new Command(Method$1.EnumerateDevices))).then(function(response) {
                if (!response)
                  return [];
                var deviceList = JSON.parse(core.Utf8.fromBase64Url(response.Data || "{}"));
                return JSON.parse(deviceList.DeviceIDs || "[]");
              });
            };
            FingerprintReader2.prototype.getDeviceInfo = function(deviceUid) {
              return this.channel.send(new Request(new Command(Method$1.GetDeviceInfo, core.Base64Url.fromJSON({ DeviceID: deviceUid })))).then(function(response) {
                var deviceInfo = JSON.parse(core.Utf8.fromBase64Url(response.Data || "null"));
                return deviceInfo;
              });
            };
            FingerprintReader2.prototype.startAcquisition = function(sampleFormat, deviceUid) {
              return this.channel.send(new Request(new Command(Method$1.StartAcquisition, core.Base64Url.fromJSON({
                DeviceID: deviceUid ? deviceUid : "00000000-0000-0000-0000-000000000000",
                SampleType: sampleFormat
              })))).then();
            };
            FingerprintReader2.prototype.stopAcquisition = function(deviceUid) {
              return this.channel.send(new Request(new Command(Method$1.StopAcquisition, core.Base64Url.fromJSON({
                DeviceID: deviceUid ? deviceUid : "00000000-0000-0000-0000-000000000000"
              })))).then();
            };
            FingerprintReader2.prototype.onConnectionFailed = function() {
              this.emit(new CommunicationFailed());
            };
            FingerprintReader2.prototype.processNotification = function(notification) {
              switch (notification.Event) {
                case NotificationType$1.Completed:
                  var completed = JSON.parse(core.Utf8.fromBase64Url(notification.Data || ""));
                  return this.emit(new SamplesAcquired(notification.Device, completed.SampleFormat, completed.Samples));
                case NotificationType$1.Error:
                  var error = JSON.parse(core.Utf8.fromBase64Url(notification.Data || ""));
                  return this.emit(new ErrorOccurred(notification.Device, error.uError));
                case NotificationType$1.Disconnected:
                  return this.emit(new DeviceDisconnected(notification.Device));
                case NotificationType$1.Connected:
                  return this.emit(new DeviceConnected(notification.Device));
                case NotificationType$1.Quality:
                  var quality = JSON.parse(core.Utf8.fromBase64Url(notification.Data || ""));
                  return this.emit(new QualityReported(notification.Device, quality.Quality));
                case NotificationType$1.Stopped:
                  return this.emit(new AcquisitionStopped(notification.Device));
                case NotificationType$1.Started:
                  return this.emit(new AcquisitionStarted(notification.Device));
                default:
                  console.log("Unknown notification: " + notification.Event);
              }
            };
            return FingerprintReader2;
          })(
            MultiCastEventSource
            //    implements FingerprintsEventSource, DeviceEventSource, CommunicationEventSource
          )
        );
        var Method$2;
        (function(Method2) {
          Method2[Method2["Init"] = 1] = "Init";
          Method2[Method2["Continue"] = 2] = "Continue";
          Method2[Method2["Term"] = 3] = "Term";
          Method2[Method2["Authenticate"] = 4] = "Authenticate";
        })(Method$2 || (Method$2 = {}));
        var MessageType$1;
        (function(MessageType2) {
          MessageType2[MessageType2["Response"] = 0] = "Response";
          MessageType2[MessageType2["Notification"] = 1] = "Notification";
        })(MessageType$1 || (MessageType$1 = {}));
        var WindowsAuthClient = (
          /** @class */
          (function(_super) {
            __extends(WindowsAuthClient2, _super);
            function WindowsAuthClient2(options) {
              var _this = _super.call(this) || this;
              _this.channel = new Channel("wia", options);
              _this.channel.onCommunicationError = _this.onConnectionFailed.bind(_this);
              return _this;
            }
            WindowsAuthClient2.prototype.on = function(event, handler) {
              return this._on(event, handler);
            };
            WindowsAuthClient2.prototype.off = function(event, handler) {
              return this._off(event, handler);
            };
            WindowsAuthClient2.prototype.init = function() {
              return this.channel.send(new Request(new Command(Method$2.Init)), 3e3).then(function(response) {
                var data = JSON.parse(response.Data || "{}");
                return { handle: data.Handle, data: data.Data };
              });
            };
            WindowsAuthClient2.prototype.continue = function(handle, data) {
              return this.channel.send(new Request(new Command(Method$2.Continue, JSON.stringify({ Handle: handle, Data: data })))).then(function(response) {
                var d = JSON.parse(response.Data || "{}");
                return d.Data;
              });
            };
            WindowsAuthClient2.prototype.term = function(handle) {
              return this.channel.send(new Request(new Command(Method$2.Term, JSON.stringify({ Handle: handle })))).then();
            };
            WindowsAuthClient2.prototype.onConnectionFailed = function() {
              this.emit(new CommunicationFailed());
            };
            return WindowsAuthClient2;
          })(MultiCastEventSource)
        );
        exports2.AcquisitionStarted = AcquisitionStarted;
        exports2.AcquisitionStopped = AcquisitionStopped;
        exports2.CardInserted = CardInserted;
        exports2.CardRemoved = CardRemoved;
        exports2.CardsReader = CardsReader;
        exports2.CommunicationFailed = CommunicationFailed;
        exports2.DeviceConnected = DeviceConnected;
        exports2.DeviceDisconnected = DeviceDisconnected;
        exports2.DeviceEvent = DeviceEvent;
        exports2.ErrorOccurred = ErrorOccurred;
        exports2.Event = Event;
        exports2.FingerprintReader = FingerprintReader;
        exports2.QualityReported = QualityReported;
        exports2.SamplesAcquired = SamplesAcquired;
        exports2.WindowsAuthClient = WindowsAuthClient;
        Object.defineProperty(exports2, "__esModule", { value: true });
      });
    }
  });

  // dp_entry.js
  var require_dp_entry = __commonJS({
    "dp_entry.js"() {
      var services = require_index_umd2();
      window.WebSdk = services;
      window.dp = { services, devices: require_index_umd3() };
    }
  });
  require_dp_entry();
})();
/*! Bundled license information:

@digitalpersona/core/dist/es5.bundles/index.umd.js:
@digitalpersona/services/dist/es5.bundles/index.umd.js:
@digitalpersona/devices/dist/es5.bundles/index.umd.js:
  (*! *****************************************************************************
      Copyright (c) Microsoft Corporation. All rights reserved.
      Licensed under the Apache License, Version 2.0 (the "License"); you may not use
      this file except in compliance with the License. You may obtain a copy of the
      License at http://www.apache.org/licenses/LICENSE-2.0
  
      THIS CODE IS PROVIDED ON AN *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
      KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
      WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
      MERCHANTABLITY OR NON-INFRINGEMENT.
  
      See the Apache Version 2.0 License for specific language governing permissions
      and limitations under the License.
      ***************************************************************************** *)
*/
