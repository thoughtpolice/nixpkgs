{ stdenv, fetchurl, kernelPatches ? [], ... } @ args:

let
  patches = kernelPatches ++
   [{ name = "remove-driver-compilation-dates";
      patch = ./linux-3-10-35-no-dates.patch;
    }];
in

import ./generic.nix (args // rec {
  version = "3.10.48";
  extraMeta.branch = "3.10";

  src = fetchurl {
    url = "mirror://kernel/linux/kernel/v3.x/linux-${version}.tar.xz";
    sha256 = "14gz998vr9jb9blbk60phq3hwnl2yipd6fykkl5bd8gai5wph2l3";
  };

  kernelPatches = patches;

  features.iwlwifi = true;
  features.efiBootStub = true;
  features.needsCifsUtils = true;
  features.canDisableNetfilterConntrackHelpers = true;
  features.netfilterRPFilter = true;
})
