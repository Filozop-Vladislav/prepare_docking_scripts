#!/bin/bash 
set -euo pipefail
echo "должны быть в директории beta_sitosterol_md"


[[ "${PWD##*/}" == "beta_sitosterol" ]] \
    || { echo "FATAL: запускать из beta_sitosterol, а мы в '${PWD##*/}'" >&2; exit 1; }

#готовим топологию белка
gmx pdb2gmx -f receptor.pdb -i protein_posre.itp -p protein.top -o protein.gro -ff amber99sb-ildn -ignh -water tip3p

#готовим топологию лиганда 
obabel beta_sitosterol_md.sdf -O ligand.mol2
antechamber -i ligand.mol2 -fi mol2 -o ligand_charged.mol2 -fo mol2 -c bcc -at gaff2 -nc 0 -pf yes

parmchk2 -i ligand_charged.mol2 -f mol2 -o ligand.frcmod -s gaff2

echo -e "source leaprc.gaff2 \nloadamberparams ligand.frcmod \nmol = loadmol2 ligand_charged.mol2 \nsaveamberparm mol ligand.prmtop ligand.inpcrd \nquit" >> tleap.in
tleap -f tleap.in

#from amber2gromacs
acpype -p ligand.prmtop -x ligand.inpcrd
mv UNL.amb2gmx/UNL_GMX.gro lig.gro && mv UNL.amb2gmx/UNL_GMX.top lig.itp
#объединяем топологии
wget https://raw.githubusercontent.com/Filozop-Vladislav/prepare_docking_scripts/main/prepare_topology.sh
chmod +x prepare_topology.sh 
./prepare_topology.sh 
#создаем ячейку необходимых раземров
gmx editconf -f protein.gro -o box.gro -c -d 0.8 -bt cubic
gmx solvate -cp box.gro -o solvated.gro -p protein.top
#добавляем ионы 
wget https://raw.githubusercontent.com/Filozop-Vladislav/prepare_docking_scripts/main/md/mdp_files/ions.mdp
gmx grompp -f ions.mdp -c solvated.gro -p protein.top -o ions.tpr
echo "SOL" | gmx genion -s ions.tpr -p protein.top -o box_ions.gro -conc 0.15 -neutral -pname NA -nname CL
#делаем минимизацию 
wget https://raw.githubusercontent.com/Filozop-Vladislav/prepare_docking_scripts/main/md/mdp_files/em.mdp
gmx grompp -f em.mdp -c box_ions.gro -p protein.top -o em.tpr
gmx mdrun -deffnm em 

#nvt equilibration
wget https://raw.githubusercontent.com/Filozop-Vladislav/prepare_docking_scripts/main/md/mdp_files/nvt.mdp 
gmx grompp -f nvt.mdp -p protein.top -c em.gro -o nvt.tpr
gmx mdrun -deffnm nvt 
#npt equilibration
wget https://raw.githubusercontent.com/Filozop-Vladislav/prepare_docking_scripts/main/md/mdp_files/npt.mdp
gmx grompp -f npt.mdp -p protein.top -c nvt.gro -o npt.tpr
gmx mdrun -deffnm npt 
#production
wget https://raw.githubusercontent.com/Filozop-Vladislav/prepare_docking_scripts/main/md/mdp_files/md.mdp
gmx grompp -f md.mdp -p protein.top -c npt.gro -o md.tpr
gmx mdrun -deffnm md
echo "done"