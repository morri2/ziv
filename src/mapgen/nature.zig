const std = @import("std");

/// Average global surface temeperature
const expected_avg_global_temperature: f32 = 14.0;

/// returns expected temprature for a given latetude. output range: ~[-17, 28]
/// input: [-1, +1] where +-1 are the poles and 0 is the equator
pub fn tempFromLatitude(lat: f32) f32 {
    return 28.1 - 23.4 * std.math.pow(f32, lat, 2) - 21.8 * std.math.pow(f32, lat, 4);
}

/// returns expected temperature for a given altetude,
/// input: altitude in km.
pub fn tempFromAltetude(alt: f32) f32 {
    return -6.5 * alt;
}

/// *Rainfall* (annual precipitation): earth-range: <100-3000+ mm
/// Europe/america/russia/china/australia: 400-750 mm  (OBS! avg over entire nation)
/// south-america/centeral-africa: 1200-2500 mm
/// south-east asia: 2500-3000+ mm
/// north-africa/middle-east/central-asia: <100-400 mm
/// slightly-north-of-south-africa/uk: 900-1200 mm
/// true-south-africa: 300-500 mm
///     lowest: Egypt 18 mm,  highest: Colombia 3240 mm
const expected_avg_global_rainfall: f32 = 990; // entire surface area (including sea)

/// Max Rainfall (mm) based on Termperature
pub fn maxRainFromTemperature(temp: f32) f32 {
    return @max(
        @min(
            (temp + 10.0) * 100,
            4000, // realistic roof :)
        ),
        0,
    );
}

/// rain from temprature (degrees) and rain_saturation_rate in range (0, 1).
pub fn rainFromTempratureAndRainSaturation(temp: f32, rain_saturation_rate: f32) f32 {
    return maxRainFromTemperature(temp) * rain_saturation_rate;
}

// elevation guidelines:
//      mount everest:      8.8 km
//      class 1 mountain:   4.5 km
//      class 3 mountain:   2.5 km
//      class 5 mountain:   1.0 km
//
//      greenland avg:      3.0 km
//      drakenberg          1.5 km  (south african mountain)
//      rocky mountains:    3.5 km
//      africa inland:      250m - 1km
//      south africa        1.0 km
//      eastern eu/russia   0- 250m
//      china               500m - 1 km
//      antarctis           2 km - 4 km
//      america not coast   250-500m
//      colombia            0-100m
//      south eu            250m
//      north eu            0-250m
// https://www.reddit.com/media?url=https%3A%2F%2Fpreview.redd.it%2Fc37v6v37seh61.png%3Fauto%3Dwebp%26s%3Daae70ef1be79d0302f3ba92917a8e0cbbb80b791

// Generally (land, excluding antarctis):
// 35% - 0-250m
// 50% - 250-1000m
// 10% - 1000-2000m
// 5%  - 2000m+
const mean_land_elevation: f32 = 840.0;

/// height_above_sea_lvl to elevation in km
/// FOR VERY SPECIFIC VALUES!! AMONG THEM: T1 =0.027 -> 250m
pub fn elevationFromHeightMap(hmv: f32) f32 {
    //return 0.04739096 + 3.97238 * hmv + 40.5418 * hmv * hmv;
    return 0.001 + 4.772791 * hmv + 37.00795 * hmv * hmv;
}
