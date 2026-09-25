package it.gdanav.gdanav.auto

import androidx.car.app.navigation.model.Maneuver
import it.gdanav.gdanav.R

/**
 * Dal tipo di manovra di Valhalla al tipo e all'icona di Android Auto. Si
 * guida a destra: le rotonde girano in senso antiorario.
 */
object IconeManovra {
    fun tipo(valhalla: Int, uscitaRotonda: Int? = null): Int = when (valhalla) {
        1, 2, 3 -> Maneuver.TYPE_DEPART
        4 -> Maneuver.TYPE_DESTINATION
        5 -> Maneuver.TYPE_DESTINATION_RIGHT
        6 -> Maneuver.TYPE_DESTINATION_LEFT
        7 -> Maneuver.TYPE_NAME_CHANGE
        9 -> Maneuver.TYPE_TURN_SLIGHT_RIGHT
        10 -> Maneuver.TYPE_TURN_NORMAL_RIGHT
        11 -> Maneuver.TYPE_TURN_SHARP_RIGHT
        12 -> Maneuver.TYPE_U_TURN_RIGHT
        13 -> Maneuver.TYPE_U_TURN_LEFT
        14 -> Maneuver.TYPE_TURN_SHARP_LEFT
        15 -> Maneuver.TYPE_TURN_NORMAL_LEFT
        16 -> Maneuver.TYPE_TURN_SLIGHT_LEFT
        18 -> Maneuver.TYPE_ON_RAMP_NORMAL_RIGHT
        19 -> Maneuver.TYPE_ON_RAMP_NORMAL_LEFT
        20 -> Maneuver.TYPE_OFF_RAMP_NORMAL_RIGHT
        21 -> Maneuver.TYPE_OFF_RAMP_NORMAL_LEFT
        23 -> Maneuver.TYPE_KEEP_RIGHT
        24 -> Maneuver.TYPE_KEEP_LEFT
        25 -> Maneuver.TYPE_MERGE_SIDE_UNSPECIFIED
        37 -> Maneuver.TYPE_MERGE_RIGHT
        38 -> Maneuver.TYPE_MERGE_LEFT
        26 -> if (uscitaRotonda != null && uscitaRotonda > 0) {
            Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW
        } else {
            Maneuver.TYPE_ROUNDABOUT_ENTER_CCW
        }
        27 -> Maneuver.TYPE_ROUNDABOUT_EXIT_CCW
        28 -> Maneuver.TYPE_FERRY_BOAT
        else -> Maneuver.TYPE_STRAIGHT
    }

    fun icona(valhalla: Int): Int = when (valhalla) {
        4, 5, 6 -> R.drawable.manovra_arrivo
        9 -> R.drawable.manovra_leggera_destra
        2, 10 -> R.drawable.manovra_destra
        11 -> R.drawable.manovra_destra_stretta
        12, 13 -> R.drawable.manovra_inversione
        14 -> R.drawable.manovra_sinistra_stretta
        3, 15 -> R.drawable.manovra_sinistra
        16 -> R.drawable.manovra_leggera_sinistra
        18, 20 -> R.drawable.manovra_uscita_destra
        19, 21 -> R.drawable.manovra_uscita_sinistra
        23 -> R.drawable.manovra_bivio_destra
        24 -> R.drawable.manovra_bivio_sinistra
        25, 37, 38 -> R.drawable.manovra_immissione
        26, 27 -> R.drawable.manovra_rotonda
        28, 29 -> R.drawable.manovra_traghetto
        else -> R.drawable.manovra_dritto
    }

    /** Dalla freccia della corsia (come la manda l'app) alla forma di Android Auto. */
    fun formaCorsia(direzione: String): Int = when (direzione) {
        "dritto" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_STRAIGHT
        "leggeraDestra" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_SLIGHT_RIGHT
        "destra" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_NORMAL_RIGHT
        "destraStretta" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_SHARP_RIGHT
        "leggeraSinistra" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_SLIGHT_LEFT
        "sinistra" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_NORMAL_LEFT
        "sinistraStretta" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_SHARP_LEFT
        "inversioneSinistra" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_U_TURN_LEFT
        "inversioneDestra" -> androidx.car.app.navigation.model.LaneDirection.SHAPE_U_TURN_RIGHT
        else -> androidx.car.app.navigation.model.LaneDirection.SHAPE_UNKNOWN
    }
}
