# shellcheck shell=bash
# Configuration Wizard - Locale Helpers
# Country to locale mapping

# Map country code to locale. $1=country_code → locale
_country_to_locale() {
  local country="${1:-us}"
  country="${country,,}" # lowercase

  # Common country to language mappings
  case "$country" in
    us | gb | au | nz | ca | ie) echo "en_${country^^}.UTF-8" ;;
    ru) echo "ru_RU.UTF-8" ;;
    ua) echo "uk_UA.UTF-8" ;;
    de | at) echo "de_${country^^}.UTF-8" ;;
    fr | be) echo "fr_${country^^}.UTF-8" ;;
    es | mx | ar | co | cl | pe) echo "es_${country^^}.UTF-8" ;;
    pt | br) echo "pt_${country^^}.UTF-8" ;;
    it) echo "it_IT.UTF-8" ;;
    nl) echo "nl_NL.UTF-8" ;;
    pl) echo "pl_PL.UTF-8" ;;
    cz) echo "cs_CZ.UTF-8" ;;
    sk) echo "sk_SK.UTF-8" ;;
    hu) echo "hu_HU.UTF-8" ;;
    ro) echo "ro_RO.UTF-8" ;;
    bg) echo "bg_BG.UTF-8" ;;
    hr) echo "hr_HR.UTF-8" ;;
    rs) echo "sr_RS.UTF-8" ;;
    si) echo "sl_SI.UTF-8" ;;
    se) echo "sv_SE.UTF-8" ;;
    no) echo "nb_NO.UTF-8" ;;
    dk) echo "da_DK.UTF-8" ;;
    fi) echo "fi_FI.UTF-8" ;;
    ee) echo "et_EE.UTF-8" ;;
    lv) echo "lv_LV.UTF-8" ;;
    lt) echo "lt_LT.UTF-8" ;;
    gr) echo "el_GR.UTF-8" ;;
    tr) echo "tr_TR.UTF-8" ;;
    il) echo "he_IL.UTF-8" ;;
    jp) echo "ja_JP.UTF-8" ;;
    cn) echo "zh_CN.UTF-8" ;;
    tw) echo "zh_TW.UTF-8" ;;
    kr) echo "ko_KR.UTF-8" ;;
    in) echo "hi_IN.UTF-8" ;;
    th) echo "th_TH.UTF-8" ;;
    vn) echo "vi_VN.UTF-8" ;;
    id) echo "id_ID.UTF-8" ;;
    my) echo "ms_MY.UTF-8" ;;
    ph) echo "en_PH.UTF-8" ;;
    sg) echo "en_SG.UTF-8" ;;
    za) echo "en_ZA.UTF-8" ;;
    eg) echo "ar_EG.UTF-8" ;;
    sa) echo "ar_SA.UTF-8" ;;
    ae) echo "ar_AE.UTF-8" ;;
    ir) echo "fa_IR.UTF-8" ;;
    *) echo "en_US.UTF-8" ;; # Default fallback
  esac
}

# Update LOCALE based on COUNTRY selection
_update_locale_from_country() {
  LOCALE=$(_country_to_locale "$COUNTRY")
  log "Set LOCALE=$LOCALE from COUNTRY=$COUNTRY"
}
