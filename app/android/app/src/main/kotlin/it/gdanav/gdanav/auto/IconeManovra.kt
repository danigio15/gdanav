package it.gdanav.gdanav.auto

import androidx.car.app.navigation.model.Maneuver
import it.gdanav.gdanav.R

/** Dal tipo di manovra di Valhalla al tipo e all'icona di Android Auto. */
object IconeManovra {
    fun tipo(valhalla: Int): Int = when (valhalla) {
        4, 5, 6 -> Maneuver.TYPE_DESTINATION
        9, 23 -> Maneuver.TYPE_TURN_SLIGHT_RIGHT
        10, 2 -> Maneuver.TYPE_TURN_NORMAL_RIGHT
        11 -> Maneuver.TYPE_TURN_SHARP_RIGHT
        12 -> Maneuver.TYPE_U_TURN_RIGHT
        13 -> Maneuver.TYPE_U_TURN_LEFT
        14 -> Maneuver.TYPE_TURN_SHARP_LEFT
        15, 3 -> Maneuver.TYPE_TURN_NORMAL_LEFT
        16, 24 -> Maneuver.TYPE_TURN_SLIGHT_LEFT
        18, 20 -> Maneuver.TYPE_OFF_RAMP_NORMAL_RIGHT
        19, 21 -> Maneuver.TYPE_OFF_RAMP_NORMAL_LEFT
        25, 37, 38 -> Maneuver.TYPE_MERGE_SIDE_UNSPECIFIED
        26, 27 -> Maneuver.TYPE_ROUNDABOUT_ENTER_CW
        28 -> Maneuver.TYPE_FERRY_BOAT
        else -> Maneuver.TYPE_STRAIGHT
    }

    fun icona(valhalla: Int): Int = when (valhalla) {
        4, 5, 6 -> R.drawable.manovra_arrivo
        9, 23 -> R.drawable.manovra_leggera_destra
        10, 2, 11, 18, 20 -> R.drawable.manovra_destra
        12, 13 -> R.drawable.manovra_inversione
        14, 15, 3, 19, 21 -> R.drawable.manovra_sinistra
        16, 24 -> R.drawable.manovra_leggera_sinistra
        26, 27 -> R.drawable.manovra_rotonda
        else -> R.drawable.manovra_dritto
    }
}
